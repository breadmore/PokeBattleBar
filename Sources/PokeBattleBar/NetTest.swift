import Foundation
import Network

/// `PokeBattleBar --nettest` — Bonjour 광고/발견, TCP 접속, 프레이밍,
/// Battler·BattleState 직렬화 왕복을 한 프로세스 안에서 실제로 확인한다.
/// 검증은 **메인 스레드에서** 돌아야 한다 — 배틀 엔진의 한 턴 계산은
/// 디버그 빌드에서 스택 프레임이 커서 협조 스레드(512KB)를 넘긴다.
/// nonisolated async 로 두면 MainActor 에서 불러도 협조 풀로 넘어간다.
@MainActor
enum NetTest {

    private final class Box: @unchecked Sendable {
        var hostGotJoin: Wire?
        var guestGotBegan: Wire?
        var guestGotAccepted: Wire?
        var rooms: [DiscoveredRoom] = []
        var errors: [String] = []
    }

    static func run() async -> Bool {
        print("=== PokeBattleBar 네트워크 검증 ===\n")
        var ok = true

        // 0) 프레이밍 단위 테스트 — 붙어서 온 프레임과 쪼개져 온 프레임을 모두 처리하는지
        ok = framingTest() && ok

        // 0-b) 프로토콜 버전 불일치가 **명확한 오류**로 잡히는지.
        //      이게 안 되면 한쪽만 업데이트했을 때 그냥 연결이 끊기고 이유를 알 수 없다.
        ok = versionTest() && ok

        // 0-c) 다른 네트워크에서 붙을 때 쓰는 주소 파싱
        ok = directAddressTest() && ok

        // 0-d) 중계기가 게임을 모른다는 성질.
        //      깨지면 앱을 올릴 때마다 남의 기계에 있는 중계기를 고쳐달라고 해야 한다.
        ok = await relayTest() && ok

        // 1) 실제 팀 준비 (직렬화 대상이 진짜 데이터여야 의미가 있다)
        guard let team = await buildTeam([87, 317]) else {
            print("✗ 팀 준비 실패")
            return false
        }
        print("  팀 준비: \(team.map(\.name).joined(separator: ", ")) ✓")

        let box = Box()
        let roomName = "nettest-\(UUID().uuidString.prefix(8))"
        let rules = BattleRules(maxTeamSize: 2, level: 50)

        // 2) 방 광고
        let host = RoomHost()
        host.onGuestMessage = { msg in
            if case .join = msg { box.hostGotJoin = msg }
        }
        host.onError = { box.errors.append($0) }
        host.start(roomName: roomName, hostName: "호스트검증", rules: rules)
        print("  방 광고 시작: \(roomName)")

        // 3) 브라우저로 자기 방 발견
        let browser = RoomBrowser()
        browser.onRooms = { box.rooms = $0 }
        browser.onError = { box.errors.append($0) }
        browser.start()

        guard let found = await waitFor(timeout: 15, label: "Bonjour 방 발견", {
            box.rooms.first { $0.name == roomName }
        }) else {
            print("✗ 15초 안에 자기 방을 발견하지 못했습니다 (로컬 네트워크 권한 문제일 수 있습니다)")
            host.stop(); browser.stop()
            return false
        }
        print("  방 발견 ✓ (호스트=\(found.hostName), 상한=\(found.teamCap), Lv=\(found.level))")
        ok = check(found.teamCap == 2, "TXT 레코드 상한 전달") && ok
        ok = check(found.level == 50, "TXT 레코드 레벨 전달") && ok
        ok = check(found.occupied == false, "TXT 레코드 빈 방 표시") && ok
        ok = check(found.protocolVersion == PokeBattleProtocol.version,
                   "TXT 레코드 프로토콜 버전 전달 (v\(found.protocolVersion))") && ok
        ok = check(found.compatible, "같은 버전은 호환으로 판정") && ok

        // 4) 게스트로 접속
        let link = PeerLink(to: found.endpoint)
        link.start(
            onMessage: { msg in
                switch msg {
                case .joinAccepted: box.guestGotAccepted = msg
                case .battleBegan:  box.guestGotBegan = msg
                default: break
                }
            },
            onState: { st in
                if case .failed(let e) = st { box.errors.append("게스트 접속 실패: \(e)") }
            }
        )

        // 5) 게스트 -> 호스트: 진짜 팀을 실어 보낸다
        // 접속이 ready 될 시간을 준다
        try? await Task.sleep(for: .milliseconds(600))
        link.send(.join(playerName: "게스트검증", team: team))

        guard let joinMsg = await waitFor(timeout: 10, label: ".join 수신", { box.hostGotJoin }) else {
            print("✗ 호스트가 .join 을 받지 못했습니다")
            host.stop(); browser.stop(); link.cancel()

            return false
        }
        guard case .join(let gotName, let gotTeam) = joinMsg else {
            print("✗ .join 형태가 아닙니다"); return false
        }
        print("  .join 수신 ✓ (이름=\(gotName), \(gotTeam.count)마리)")
        ok = check(gotName == "게스트검증", "플레이어 이름 왕복") && ok
        ok = check(identical(team, gotTeam), "Battler 팀 직렬화 왕복 (기술·스탯 포함)") && ok
        ok = check(encodingIsDeterministic(team), "와이어 포맷이 결정적 (딕셔너리 순서 고정)") && ok

        // 6) 호스트 -> 게스트: BattleState 를 실어 보낸다
        let st = BattleState(
            rules: rules,
            sides: [SideState(playerName: "호스트검증", team: team, activeIndex: 0),
                    SideState(playerName: "게스트검증", team: gotTeam, activeIndex: 1)],
            turn: 7,
            phase: .awaitingReplacement([1]),
            log: ["첫 줄", "둘째 줄 — 한글 잘 가나?"]
        )
        host.send(.joinAccepted(rules: rules, hostName: "호스트검증", yourSide: 1))
        host.send(.battleBegan(state: st))

        guard let began = await waitFor(timeout: 10, label: ".battleBegan 수신", { box.guestGotBegan }) else {
            print("✗ 게스트가 .battleBegan 을 받지 못했습니다")
            host.stop(); browser.stop(); link.cancel()
            return false
        }
        ok = check(box.guestGotAccepted != nil, "연달아 보낸 .joinAccepted 도 도착") && ok

        guard case .battleBegan(let gotState) = began else {
            print("✗ .battleBegan 형태가 아닙니다"); return false
        }
        print("  .battleBegan 수신 ✓ (턴=\(gotState.turn), 로그 \(gotState.log.count)줄)")
        ok = check(gotState.turn == 7, "turn 왕복") && ok
        ok = check(gotState.phase == .awaitingReplacement([1]), "phase(연관값) 왕복") && ok
        ok = check(gotState.log == st.log, "로그 한글 왕복") && ok
        ok = check(gotState.sides[1].activeIndex == 1, "activeIndex 왕복") && ok
        ok = check(identical(st.sides[0].team, gotState.sides[0].team), "BattleState 내부 팀 왕복") && ok

        // 7) 두 번째 게스트는 거절되어야 한다 (1:1 전용)
        let second = PeerLink(to: found.endpoint)
        let rejected = Box()
        second.start(
            onMessage: { msg in if case .joinRejected = msg { rejected.hostGotJoin = msg } },
            onState: { _ in }
        )
        try? await Task.sleep(for: .milliseconds(600))
        second.send(.join(playerName: "난입자", team: team))
        let gotReject = await waitFor(timeout: 8, label: "두 번째 접속 거절", { rejected.hostGotJoin })
        ok = check(gotReject != nil, "이미 찬 방은 두 번째 접속을 거절") && ok
        second.cancel()

        host.stop(); browser.stop(); link.cancel()

        if !box.errors.isEmpty {
            print("\n  경고/오류 로그:")
            for e in Set(box.errors) { print("    · \(e)") }
        }

        // MARK: 번들이 Bonjour 서비스 타입을 다 선언했는가
        //
        // 선언이 빠지면 macOS 14+ 가 광고·검색을 **조용히** 막는다.
        // 번들 밖에서 바이너리를 직접 돌리면 제한이 없어 통과하므로
        // (진단 도구가 통과해도 배포본이 실패할 수 있다) 여기서 잡는다.
        // MARK: 업데이트 버전 비교
        //
        // 문자열로 비교하면 "1.10.0" < "1.9.0" 이 되어 업데이트를 놓친다.
        print("\n-- 업데이트 버전 비교 --")
        ok = check(UpdateChecker.isNewer("1.11.0", than: "1.10.0"), "1.11.0 > 1.10.0") && ok
        ok = check(UpdateChecker.isNewer("1.10.0", than: "1.9.0"),
                   "1.10.0 > 1.9.0 (문자열 비교로는 틀린다)") && ok
        ok = check(UpdateChecker.isNewer("2.0.0", than: "1.99.99"), "2.0.0 > 1.99.99") && ok
        ok = check(!UpdateChecker.isNewer("1.10.0", than: "1.10.0"), "같은 버전은 업데이트 아님") && ok
        ok = check(!UpdateChecker.isNewer("1.9.0", than: "1.10.0"), "구버전은 업데이트 아님") && ok
        ok = check(UpdateChecker.normalize("v1.11.0") == "1.11.0", "태그의 v 를 떼어낸다") && ok
        ok = check(UpdateChecker.isNewer("1.11", than: "1.10.5"), "자리 수가 달라도 비교된다") && ok

        print("\n-- Bonjour 서비스 선언 --")
        let usedTypes = [pokeBattleServiceType, pokeLobbyServiceType]
        let plistURL = Bundle.main.bundleURL.appending(path: "Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = plist as? [String: Any],
           let declared = dict["NSBonjourServices"] as? [String] {
            for t in usedTypes {
                ok = check(declared.contains(t), "Info.plist 에 \(t) 선언") && ok
            }
        } else {
            print("  · 번들 밖 실행이라 건너뜁니다 — 배포본은 앱 번들 안의")
            print("    실행 파일로 검증해야 합니다")
        }

        print(ok ? "\n✓ 네트워크 검증 통과" : "\n✗ 네트워크 검증 실패")
        return ok
    }

    // MARK: 중계 — 게임을 모른다는 성질

    /// 테스트용 최소 중계기.
    ///
    /// `scripts/relay.py` 와 **같은 규약만** 지킨다: 길이 4바이트+JSON 핸드셰이크를
    /// 한 프레임 읽고, 짝이 맞으면 그 뒤로는 바이트를 그대로 흘린다.
    /// 파이썬 없이 돌려야 릴리스 게이트(--testall)에 넣을 수 있다.
    private final class FakeRelay: @unchecked Sendable {
        private var listener: NWListener?
        private let queue = DispatchQueue(label: "poke.fakerelay")
        private let lock = NSLock()
        private var waitingHost: (conn: NWConnection, name: String)?

        private var ready = false
        /// 리스너가 실제로 열린 뒤에야 포트가 정해진다 —
        /// 바로 읽으면 아직 바인딩 전이라 아무도 붙지 못한다.
        var boundPort: UInt16? {
            lock.lock(); defer { lock.unlock() }
            return ready ? listener?.port?.rawValue : nil
        }
        var failure: String?

        func start() throws {
            let l = try NWListener(using: .tcp)
            l.stateUpdateHandler = { [weak self] st in
                guard let self else { return }
                switch st {
                case .ready:
                    self.lock.lock(); self.ready = true; self.lock.unlock()
                case .failed(let e):
                    self.failure = "테스트 중계기 실패: \(e.localizedDescription)"
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: self?.queue ?? .main)
                self?.readHandshake(conn, buffer: Data())
            }
            listener = l
            l.start(queue: queue)
        }

        func stop() {
            listener?.cancel(); listener = nil
            lock.lock(); let w = waitingHost?.conn; waitingHost = nil; lock.unlock()
            w?.cancel()
        }

        /// 핸드셰이크 한 프레임이 다 올 때까지 모은다. 남은 바이트는 그대로 넘긴다.
        private func readHandshake(_ conn: NWConnection, buffer: Data) {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, _ in
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }
                if let hello = try? RelayCodec.decode(RelayHello.self, from: &buf) {
                    self.pair(conn, hello: hello, leftover: buf)
                    return
                }
                if done { conn.cancel(); return }
                self.readHandshake(conn, buffer: buf)
            }
        }

        private func send(_ conn: NWConnection, _ frame: RelayServerFrame) {
            guard let data = try? RelayCodec.encode(frame) else { return }
            conn.send(content: data, completion: .contentProcessed { _ in })
        }

        private func pair(_ conn: NWConnection, hello: RelayHello, leftover: Data) {
            switch hello.role {
            case .host:
                lock.lock(); waitingHost = (conn, hello.name); lock.unlock()
                send(conn, RelayServerFrame(ok: true, registered: true))
            case .guest:
                lock.lock(); let host = waitingHost; waitingHost = nil; lock.unlock()
                guard let host else {
                    send(conn, RelayServerFrame(ok: false, reason: "방이 없습니다"))
                    conn.cancel()
                    return
                }
                send(host.conn, RelayServerFrame(ok: true, paired: true, peer: hello.name))
                send(conn, RelayServerFrame(ok: true, paired: true, peer: host.name))
                // 이 뒤로는 게임을 모른다 — 바이트를 그대로 흘린다
                if !leftover.isEmpty {
                    host.conn.send(content: leftover, completion: .contentProcessed { _ in })
                }
                pump(host.conn, to: conn)
                pump(conn, to: host.conn)
            case .lobby:
                send(conn, RelayServerFrame(ok: true, registered: true))
            }
        }

        private func pump(_ from: NWConnection, to: NWConnection) {
            from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, err in
                if let data, !data.isEmpty {
                    to.send(content: data, completion: .contentProcessed { _ in })
                }
                if done || err != nil { from.cancel(); to.cancel(); return }
                self?.pump(from, to: to)
            }
        }
    }

    /// 중계기를 거쳐도 **버전 협상은 두 앱 사이에서** 끝나는지.
    ///
    /// 이게 깨지면 앱 프로토콜을 올릴 때마다 중계기를 다시 배포해야 한다 —
    /// 남의 기계에 띄워둔 중계기를 매번 고쳐달라고 부탁해야 한다는 뜻이다.
    /// 그래서 "중계기는 게임을 모른다" 를 회귀로 잡아둔다.
    private static func relayTest() async -> Bool {
        print("-- 중계 (게임을 모르는 파이프) --")
        var ok = true

        guard let team = await buildTeam([87]) else {
            print("  ✗ 팀 준비 실패"); return false
        }

        // 1라운드: 짝 맞춤 + 양방향 Wire 왕복
        let relay = FakeRelay()
        do { try relay.start() } catch {
            print("  ✗ 테스트 중계기 시작 실패: \(error)"); return false
        }
        guard let port = await waitFor(timeout: 5, label: "중계기 준비", { relay.boundPort }),
              let p = NWEndpoint.Port(rawValue: port) else {
            print("  ✗ 테스트 중계기가 열리지 않았다 \(relay.failure ?? "")")
            relay.stop(); return false
        }
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: p)

        let box = Box()
        let host = RoomHost()
        host.onGuestMessage = { msg in if case .chat = msg { box.hostGotJoin = msg } }
        host.onGuestConnected = { link in link.send(.chat(from: "호스트", text: "내려간다")) }
        host.onError = { box.errors.append($0) }
        host.startRelay(server: endpoint, room: "T1", secret: nil,
                        hostName: "중계호스트", rules: .init(maxTeamSize: 1, level: 50))

        let guest = PeerLink(to: endpoint)
        guest.startRelay(
            hello: RelayHello(role: .guest, room: "T1", name: "중계게스트", secret: nil),
            onRegistered: { _ in },
            onPaired: { _ in guest.send(.chat(from: "게스트", text: "올라간다")) },
            onRejected: { box.errors.append("거절: \($0)") },
            onMessage: { msg in if case .chat = msg { box.guestGotBegan = msg } },
            onState: { if case .failed(let e) = $0 { box.errors.append("게스트: \(e)") } }
        )

        let up = await waitFor(timeout: 10, label: "게스트→호스트", { box.hostGotJoin })
        let down = await waitFor(timeout: 10, label: "호스트→게스트", { box.guestGotBegan })
        ok = check(up != nil, "중계를 거쳐 게스트→호스트 메시지 도착") && ok
        ok = check(down != nil, "중계를 거쳐 호스트→게스트 메시지 도착") && ok
        if up == nil || down == nil, !box.errors.isEmpty {
            for e in Set(box.errors) { print("      · \(e)") }
        }
        guest.cancel(); host.stop(); relay.stop()
        _ = team

        // 2라운드: 상대가 **다른 프로토콜 버전**이면 중계기가 아니라 앱이 알아낸다
        let relay2 = FakeRelay()
        do { try relay2.start() } catch { print("  ✗ 중계기 시작 실패"); return false }
        guard let port2 = await waitFor(timeout: 5, label: "중계기 준비", { relay2.boundPort }),
              let p2 = NWEndpoint.Port(rawValue: port2) else {
            print("  ✗ 테스트 중계기가 열리지 않았다 \(relay2.failure ?? "")")
            relay2.stop(); return false
        }
        let endpoint2 = NWEndpoint.hostPort(host: "127.0.0.1", port: p2)

        let box2 = Box()
        let host2 = RoomHost()
        host2.onProtocolError = { box2.errors.append($0) }
        host2.onError = { _ in }
        host2.startRelay(server: endpoint2, room: "T2", secret: nil,
                         hostName: "중계호스트", rules: .default)

        // 게스트는 손으로 만든다 — 다른 버전 프레임을 보내려면 raw 연결이 필요하다
        let raw = NWConnection(to: endpoint2, using: .tcp)
        let rawQueue = DispatchQueue(label: "poke.rawguest")
        raw.stateUpdateHandler = { st in
            guard st == .ready else { return }
            if let hello = try? RelayCodec.encode(
                RelayHello(role: .guest, room: "T2", name: "구버전클라", secret: nil)) {
                raw.send(content: hello, completion: .contentProcessed { _ in })
            }
            // 짝이 맞았다는 응답을 기다린 뒤, 미래 버전 프레임을 흘려보낸다
            raw.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                let body = Data(#"{"v":\#(PokeBattleProtocol.version + 1),"msg":{"leave":{}}}"#.utf8)
                var out = Data()
                var len = UInt32(body.count).bigEndian
                withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
                out.append(body)
                raw.send(content: out, completion: .contentProcessed { _ in })
            }
        }
        raw.start(queue: rawQueue)

        let detected = await waitFor(timeout: 10, label: "버전 불일치 감지", {
            box2.errors.first { $0.contains("최신") || $0.contains("구버전") }
        })
        ok = check(detected != nil,
                   "중계기를 거쳐도 앱이 버전 불일치를 알아낸다") && ok
        if let detected { print("      \(detected)") }
        ok = check(box2.errors.allSatisfy { !$0.contains("해석할 수 없습니다") },
                   "그냥 끊기지 않고 이유가 붙는다") && ok

        raw.cancel(); host2.stop(); relay2.stop()
        print("")
        return ok
    }

    // MARK: 프로토콜 버전

    private static func versionTest() -> Bool {
        var ok = true

        // 다른 버전이 보낸 프레임을 손으로 만들어 넣는다
        func frame(v: Int, json: String) -> Data {
            let body = Data(#"{"v":\#(v),"msg":\#(json)}"#.utf8)
            var out = Data()
            var len = UInt32(body.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(body)
            return out
        }

        // 미래 버전
        var buf = frame(v: PokeBattleProtocol.version + 1, json: #"{"leave":{}}"#)
        do {
            _ = try WireCodec.drain(&buf)
            print("  ✗ 상위 버전 프레임이 오류 없이 통과했다")
            ok = false
        } catch let e as WireError where e.isVersionProblem {
            print("  ✓ 상위 버전 거부: \(e.errorDescription ?? "")")
        } catch {
            print("  ✗ 상위 버전에서 엉뚱한 오류: \(error)")
            ok = false
        }

        // 구버전
        buf = frame(v: 1, json: #"{"leave":{}}"#)
        do {
            _ = try WireCodec.drain(&buf)
            print("  ✗ 구버전 프레임이 오류 없이 통과했다")
            ok = false
        } catch let e as WireError where e.isVersionProblem {
            print("  ✓ 구버전 거부: \(e.errorDescription ?? "")")
        } catch {
            print("  ✗ 구버전에서 엉뚱한 오류: \(error)")
            ok = false
        }

        // 같은 버전은 통과해야 한다
        do {
            var good = try WireCodec.encode(.leave)
            let got = try WireCodec.drain(&good)
            ok = check(got.count == 1, "같은 버전은 정상 통과") && ok
        } catch {
            print("  ✗ 같은 버전인데 실패: \(error)")
            ok = false
        }

        // 버전 확인이 본문 해석보다 **먼저** 일어나는지 —
        // 본문이 완전히 깨져 있어도 버전 오류로 잡혀야 한다
        buf = frame(v: 99, json: #"{"이건":"없는 메시지 형식"}"#)
        do {
            _ = try WireCodec.drain(&buf)
            print("  ✗ 깨진 본문 + 다른 버전이 통과했다")
            ok = false
        } catch let e as WireError where e.isVersionProblem {
            print("  ✓ 본문이 깨져 있어도 버전 오류로 먼저 잡힘")
        } catch {
            print("  ✗ 버전 확인이 본문 해석보다 늦다 — 원인 파악이 불가능해진다: \(error)")
            ok = false
        }

        return ok
    }

    // MARK: 프레이밍 단위 테스트

    private static func framingTest() -> Bool {
        var ok = true
        do {
            let a = Wire.chooseLead(index: 3)
            let b = Wire.action(.replace(teamIndex: 5))
            let c = Wire.leave

            // 세 프레임을 한 덩어리로 붙여서 준다
            var buf = Data()
            buf.append(try WireCodec.encode(a))
            buf.append(try WireCodec.encode(b))
            buf.append(try WireCodec.encode(c))
            let drained = try WireCodec.drain(&buf)
            ok = check(drained.count == 3, "붙어 온 3프레임 분리") && ok
            ok = check(buf.isEmpty, "분리 후 버퍼 비움") && ok

            // 프레임을 반씩 쪼개서 준다 (TCP 는 경계를 보장하지 않는다)
            let whole = try WireCodec.encode(a)
            var partial = whole.prefix(3)   // 길이 헤더도 안 찬 상태
            var pbuf = Data(partial)
            var got = try WireCodec.drain(&pbuf)
            ok = check(got.isEmpty, "헤더 미완성이면 대기") && ok

            partial = whole.prefix(whole.count - 2)
            pbuf = Data(partial)
            got = try WireCodec.drain(&pbuf)
            ok = check(got.isEmpty, "본문 미완성이면 대기") && ok

            pbuf.append(whole.suffix(2))
            got = try WireCodec.drain(&pbuf)
            ok = check(got.count == 1, "나머지 도착 후 조립") && ok
            if case .chooseLead(let i) = got.first { ok = check(i == 3, "쪼개진 프레임 내용 보존") && ok }
        } catch {
            print("  ✗ 프레이밍 테스트 예외: \(error)")
            ok = false
        }
        return ok
    }

    // MARK: 헬퍼

    private static func check(_ cond: Bool, _ label: String) -> Bool {
        print(cond ? "  ✓ \(label)" : "  ✗ \(label)")
        return cond
    }

    /// 조건이 만족될 때까지 폴링하며 기다린다.
    private static func waitFor<T>(timeout: Double, label: String, _ probe: @escaping () -> T?) async -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let v = probe() { return v }
            try? await Task.sleep(for: .milliseconds(120))
        }
        return nil
    }

    /// 필드 단위 비교. 직렬화 **바이트**를 비교하면 안 된다 —
    /// 딕셔너리 인코딩 순서는 인스턴스마다 달라서 내용이 같아도 바이트가 다르다.
    private static func identical(_ a: [Battler], _ b: [Battler]) -> Bool {
        guard a.count == b.count else {
            print("      (마리 수 불일치: \(a.count) vs \(b.count))")
            return false
        }
        for (x, y) in zip(a, b) where x != y {
            print("      (불일치: \(x.name))")
            if x.stats != y.stats { print("        스탯 \(x.stats) vs \(y.stats)") }
            if x.moves != y.moves {
                print("        기술 \(x.moves.map(\.def.name)) vs \(y.moves.map(\.def.name))")
            }
            if x.maxHP != y.maxHP { print("        maxHP \(x.maxHP) vs \(y.maxHP)") }
            if x.types != y.types { print("        타입 \(x.types) vs \(y.types)") }
            return false
        }
        return true
    }

    /// 와이어 포맷이 결정적인지 (진단 편의를 위해 확인한다)
    private static func encodingIsDeterministic(_ team: [Battler]) -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let a = try? enc.encode(team),
              let decoded = try? JSONDecoder().decode([Battler].self, from: a),
              let b = try? enc.encode(decoded) else { return false }
        return a == b
    }

    private static func buildTeam(_ ids: [Int]) async -> [Battler]? {
        var out: [Battler] = []
        for (i, id) in ids.enumerated() {
            guard let sp = try? await PokeAPI.shared.species(id) else { return nil }
            let slot = RosterSlot(id: "net-\(i)-\(id)", speciesID: id, nature: "bold",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            let moves = await MovesetStore.shared.moveset(for: slot, species: sp)
            guard !moves.isEmpty else { return nil }
            out.append(Battler.make(slot: slot, species: sp, moves: moves, level: 50))
        }
        return out
    }
    /// 주소로 직접 접속할 때 쓰는 주소 파싱.
    ///
    /// 여기가 틀리면 다른 네트워크 접속이 통째로 안 된다 —
    /// 특히 IPv6 의 콜론을 포트 구분으로 착각하기 쉽다.
    private static func directAddressTest() -> Bool {
        var ok = true
        func check(_ input: String, host: String?, port: UInt16?, _ label: String) {
            let e = DirectConnect.endpoint(from: input)
            guard let host, let port else {
                let pass = e == nil
                print(pass ? "  ✓ \(label)" : "  ✗ \(label) — 받아들이면 안 되는 주소다")
                ok = pass && ok
                return
            }
            guard case .hostPort(let h, let p)? = e else {
                print("  ✗ \(label) — 파싱 실패")
                ok = false
                return
            }
            let hs = "\(h)".split(separator: "%").first.map(String.init) ?? "\(h)"
            let pass = hs == host && p.rawValue == port
            print(pass ? "  ✓ \(label)"
                       : "  ✗ \(label) — \(hs):\(p.rawValue) (기대 \(host):\(port))")
            ok = pass && ok
        }
        print("-- 직접 접속 주소 --")
        let def = RoomHost.preferredPort
        check("100.64.1.2:51234", host: "100.64.1.2", port: 51234, "IPv4 + 포트")
        check("100.64.1.2", host: "100.64.1.2", port: def, "포트를 생략하면 기본 포트")
        check("  192.168.0.5:7000  ", host: "192.168.0.5", port: 7000, "앞뒤 공백을 무시한다")
        check("example.com:51234", host: "example.com", port: 51234, "호스트 이름")
        check("[fd00::1]:51234", host: "fd00::1", port: 51234, "IPv6 (대괄호)")
        check("fd00::1", host: "fd00::1", port: def, "IPv6 (포트 없음 — 콜론을 포트로 보지 않는다)")
        check("", host: nil, port: nil, "빈 문자열은 거절한다")
        check("   ", host: nil, port: nil, "공백만 있으면 거절한다")

        // 호스트가 안내하는 주소에 쓸모없는 것이 섞이지 않는지
        let addrs = DirectConnect.myAddresses(port: def)
        let clean = !addrs.contains { $0.address.hasPrefix("127.")
                                   || $0.address.hasPrefix("169.254") }
        print(clean ? "  ✓ 안내 주소에 루프백·링크로컬이 없다"
                    : "  ✗ 안내 주소에 쓸 수 없는 주소가 섞였다")
        ok = clean && ok
        print("    안내 주소: \(addrs.map(\.address).joined(separator: ", "))")
        print("")
        return ok
    }

}
