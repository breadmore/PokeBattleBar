import Foundation
import Network

/// `PokeBattleBar --nettest` — Bonjour 광고/발견, TCP 접속, 프레이밍,
/// Battler·BattleState 직렬화 왕복을 한 프로세스 안에서 실제로 확인한다.
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

        print(ok ? "\n✓ 네트워크 검증 통과" : "\n✗ 네트워크 검증 실패")
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
}
