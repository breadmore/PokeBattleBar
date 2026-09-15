import Foundation

/// 같은 맥에서 앱을 두 개 띄웠을 때 서로 방이 보이는지 확인하는 진단.
///
/// 한쪽을 `--lanprobe host`, 다른 쪽을 `--lanprobe browse` 로 **따로 실행**해야
/// 의미가 있다. 한 프로세스 안에서 하는 검사(--nettest)로는
/// 프로세스 경계를 넘는 Bonjour 광고가 실제로 보이는지 알 수 없다.
/// 검증은 **메인 스레드에서** 돌아야 한다 — 배틀 엔진의 한 턴 계산은
/// 디버그 빌드에서 스택 프레임이 커서 협조 스레드(512KB)를 넘긴다.
/// nonisolated async 로 두면 MainActor 에서 불러도 협조 풀로 넘어간다.
@MainActor
enum LanProbe {
    static func run(role: String, seconds: Int) async -> Bool {
        let tag = TestProfile.tag ?? "?"
        switch role {
        case "host":
            let host = RoomHost()
            let roomName = "probe-\(tag)"
            host.onError = { print("  ✗ \($0)") }
            host.start(roomName: roomName, hostName: "probe-\(tag)",
                       rules: .default, modeSummary: "진단")
            print("[\(tag)] 방 광고 시작: \(roomName) — \(seconds)초 유지")
            try? await Task.sleep(for: .seconds(seconds))
            host.stop()
            print("[\(tag)] 광고 종료")
            return true

        case "browse":
            let browser = RoomBrowser()
            let seen = SeenRooms()
            browser.onError = { print("  ✗ \($0)") }
            browser.onRooms = { rooms in Task { await seen.add(rooms) } }
            browser.start()
            print("[\(tag)] \(seconds)초 동안 방 검색…")
            try? await Task.sleep(for: .seconds(seconds))
            browser.stop()
            let found = await seen.all
            for r in found {
                print("  · \(r) ")
            }
            // 내가 띄우지 않은 방(다른 프로세스의 방)이 하나라도 보여야 통과
            let others = found.filter { !$0.contains("probe-\(tag)") }
            if others.isEmpty {
                print("  ✗ 다른 프로세스의 방을 찾지 못했습니다 (총 \(found.count)개)")
                return false
            }
            print("  ✓ 다른 프로세스의 방 \(others.count)개 발견 — 같은 맥에서 배틀 가능")
            return true

        case "lobby":
            // 서로를 발견하고 초대를 주고받는지 본다.
            // 두 프로세스를 --lanprobe lobby 로 같이 띄워야 의미가 있다.
            let me = LobbyPresence()
            let seen = SeenPeers()
            me.onError = { print("  ✗ \($0)") }
            me.onPeers = { peers in Task { await seen.add(peers) } }
            me.onInvite = { from, room in
                Task { await seen.gotInvite(from: from, room: room) }
                print("[\(tag)] 초대 받음: \(from) → \(room)")
            }
            me.onDeclined = { who in print("[\(tag)] 거절 회신: \(who)") }
            me.start(displayName: "probe-\(tag)")
            print("[\(tag)] 로비 광고: probe-\(tag) (\(me.serviceName))")

            // 상대를 찾을 시간을 준다
            try? await Task.sleep(for: .seconds(min(6, seconds)))
            let found = await seen.names
            for n in found { print("  · 발견: \(n)") }

            // A 쪽만 초대를 보낸다 (양쪽이 보내면 누가 받았는지 헷갈린다)
            if tag == "A", let target = await seen.first {
                print("[\(tag)] \(target.displayName) 에게 초대 전송")
                me.sendInvite(to: target, roomName: "probe-room-A")
            }

            try? await Task.sleep(for: .seconds(seconds))
            let invite = await seen.invite
            me.stop()

            if found.isEmpty {
                print("  ✗ 다른 프로세스의 로비를 찾지 못했습니다")
                return false
            }
            print("  ✓ 다른 프로세스의 로비 \(found.count)개 발견")
            if tag == "B" {
                guard let invite else {
                    print("  ✗ 초대를 받지 못했습니다")
                    return false
                }
                print("  ✓ 초대 수신 확인: \(invite.0) → \(invite.1)")
            }
            return true

        // 중계 서버를 거쳐 실제로 만나지는지 본다.
        // 두 프로세스를 relayhost / relayguest 로 띄우고, 중계기는 따로 돌린다:
        //   python3 scripts/relay.py
        //   POKEBATTLE_RELAY=127.0.0.1 POKEBATTLE_ROOM=TEST1 ... --lanprobe relayhost
        //   POKEBATTLE_RELAY=127.0.0.1 POKEBATTLE_ROOM=TEST1 ... --lanprobe relayguest
        case "relayhost", "relayguest":
            let env = ProcessInfo.processInfo.environment
            let addr = env["POKEBATTLE_RELAY"] ?? "127.0.0.1"
            let room = RelayConfig.normalize(room: env["POKEBATTLE_ROOM"] ?? "TEST1")
            let secret = env["POKEBATTLE_RELAY_SECRET"]
            guard let endpoint = DirectConnect.endpoint(from: addr,
                                                        defaultPort: RelayConfig.defaultPort) else {
                print("  ✗ 중계 주소를 알아볼 수 없습니다: \(addr)")
                return false
            }
            let box = RelayProbeBox()

            if role == "relayhost" {
                let host = RoomHost()
                host.onError = { print("  ✗ \($0)") }
                host.onRelayRegistered = { print("[\(tag)] 방 등록됨 — 코드 \(room)") }
                host.onGuestConnected = { link in
                    print("[\(tag)] 짝 성사 — 상대가 붙었다")
                    Task { await box.sawPeer() }
                    link.send(.chat(from: "relayhost", text: "호스트가 보낸다"))
                }
                host.onGuestMessage = { msg in
                    if case .chat(let from, let text) = msg {
                        print("[\(tag)] 수신: \(from) — \(text)")
                        Task { await box.sawMessage() }
                    }
                }
                host.startRelay(server: endpoint, room: room, secret: secret,
                                hostName: "relayhost", rules: .default, modeSummary: "진단")
                print("[\(tag)] 중계 서버 \(addr) 에 방 \(room) 등록 시도 — \(seconds)초")
                try? await Task.sleep(for: .seconds(seconds))
                host.stop()
            } else {
                let link = PeerLink(to: endpoint)
                link.startRelay(
                    hello: RelayHello(role: .guest, room: room, name: "relayguest", secret: secret),
                    onRegistered: { _ in },
                    onPaired: { peer in
                        print("[\(tag)] 짝 성사 — 상대 \(peer ?? "?")")
                        Task { await box.sawPeer() }
                        link.send(.chat(from: "relayguest", text: "게스트가 보낸다"))
                    },
                    onRejected: { why in print("  ✗ 거절: \(why)") },
                    onMessage: { msg in
                        if case .chat(let from, let text) = msg {
                            print("[\(tag)] 수신: \(from) — \(text)")
                            Task { await box.sawMessage() }
                        }
                    },
                    onState: { st in
                        if case .failed(let e) = st { print("  ✗ 접속 실패: \(e)") }
                    }
                )
                print("[\(tag)] 중계 서버 \(addr) 의 방 \(room) 에 참가 시도 — \(seconds)초")
                try? await Task.sleep(for: .seconds(seconds))
                link.cancel()
            }

            let paired = await box.paired, got = await box.gotMessage
            print(paired ? "  ✓ 중계로 짝이 맞았다" : "  ✗ 짝이 맞지 않았다")
            print(got ? "  ✓ 중계를 통해 Wire 메시지가 오갔다"
                      : "  ✗ 메시지를 받지 못했다")
            return paired && got

        // 중계 로비 — 그 중계기에 붙어 있는 사람과 열린 방이 보이는지.
        // relayhost 를 같이 띄워두면 열린 방까지 확인된다.
        case "relaylobby":
            let env = ProcessInfo.processInfo.environment
            let addr = env["POKEBATTLE_RELAY"] ?? "127.0.0.1"
            guard let endpoint = DirectConnect.endpoint(from: addr,
                                                        defaultPort: RelayConfig.defaultPort) else {
                print("  ✗ 중계 주소를 알아볼 수 없습니다: \(addr)")
                return false
            }
            let seen = SeenLobby()
            let lobby = RelayLobby()
            lobby.onConnectedChanged = { on in print("[\(tag)] 접속 \(on ? "됨" : "끊김")") }
            lobby.onRejected = { print("  ✗ 거절: \($0)") }
            lobby.onError = { print("  · \($0)") }
            lobby.onSnapshot = { snap in
                Task { await seen.add(snap) }
            }
            lobby.start(server: endpoint, displayName: "probe-\(tag)",
                        secret: env["POKEBATTLE_RELAY_SECRET"])
            print("[\(tag)] 중계 로비 \(addr) 접속 — \(seconds)초")
            try? await Task.sleep(for: .seconds(seconds))
            let connected = lobby.isConnected
            lobby.stop()

            let peers = await seen.peers, rooms = await seen.rooms, count = await seen.updates
            print("  \(connected ? "✓" : "✗") 로비에 붙어 있다")
            print("  \(count > 0 ? "✓" : "✗") 스냅샷 \(count)회 수신")
            print("    접속자: \(peers.isEmpty ? "(없음)" : peers.joined(separator: ", "))")
            print("    열린 방: \(rooms.isEmpty ? "(없음)" : rooms.joined(separator: ", "))")
            return connected && count > 0

        // 중계 로비 초대 — 보내는 쪽(A)과 받는 쪽(B)을 같이 띄운다.
        // A 는 방까지 등록해야 초대가 통한다 (중계기가 방 존재를 확인한다).
        case "relayinvite":
            let env = ProcessInfo.processInfo.environment
            let addr = env["POKEBATTLE_RELAY"] ?? "127.0.0.1"
            let room = RelayConfig.normalize(room: env["POKEBATTLE_ROOM"] ?? "INV1")
            let secret = env["POKEBATTLE_RELAY_SECRET"]
            guard let endpoint = DirectConnect.endpoint(from: addr,
                                                        defaultPort: RelayConfig.defaultPort) else {
                print("  ✗ 중계 주소를 알아볼 수 없습니다: \(addr)")
                return false
            }
            let seen = SeenInvite()
            let lobby = RelayLobby()
            lobby.onRejected = { print("  ✗ 거절: \($0)") }
            lobby.onError = { print("  · \($0)") }
            lobby.onSnapshot = { snap in Task { await seen.note(snap.peers) } }
            lobby.onInvite = { from, fromCid, room in
                print("[\(tag)] 초대 받음: \(from)#\(fromCid.map(String.init) ?? "?") → 방 \(room)")
                Task { await seen.got(from: from, cid: fromCid, room: room) }
            }
            lobby.onDeclined = { who in
                print("[\(tag)] 거절 회신: \(who)")
                Task { await seen.declined(who) }
            }
            lobby.onInviteFailed = { who, why in
                print("[\(tag)] 전달 실패: \(who) — \(why)")
                Task { await seen.failed(why) }
            }

            // A 는 방을 등록해 둔다 (초대가 가리킬 방이 있어야 한다)
            var host: RoomHost?
            if tag == "A" {
                let h = RoomHost()
                h.onError = { print("  ✗ \($0)") }
                h.startRelay(server: endpoint, room: room, secret: secret,
                             hostName: "probe-A", rules: .default, modeSummary: "진단")
                host = h
            }

            lobby.start(server: endpoint, displayName: "probe-\(tag)", secret: secret)
            print("[\(tag)] 중계 로비 접속 — \(seconds)초")

            // 상대가 로비에 들어올 시간을 준다
            try? await Task.sleep(for: .seconds(min(5, seconds)))
            if tag == "A" {
                print("[A] probe-B 에게 초대 전송 (방 \(room))")
                lobby.sendInvite(to: "probe-B", cid: await seen.cidOf("probe-B"), room: room)
            }
            try? await Task.sleep(for: .seconds(seconds))

            // B 는 받은 초대를 거절해서 회신 경로까지 확인한다
            if tag == "B", let got = await seen.invite {
                lobby.decline(to: got.name, cid: got.cid)
                try? await Task.sleep(for: .seconds(2))
            }
            // **A 는 그 거절이 돌아올 때까지 기다린다.** 둘은 같은 순간에
            // 깨어나므로, 여기서 바로 끊으면 B 가 보내는 찰나에 A 가 연결을
            // 닫아 회신을 영영 못 본다.
            if tag == "A" {
                for _ in 0..<40 {
                    if await seen.settled { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            lobby.stop()
            host?.stop()

            if tag == "A" {
                let declined = await seen.declinedBy
                let failure = await seen.failure
                if let failure {
                    print("  ✗ 초대가 전달되지 않았다: \(failure)")
                    return false
                }
                print(declined != nil ? "  ✓ 거절 회신을 받았다 (\(declined!))"
                                      : "  ✗ 회신이 없었다")
                return declined != nil
            } else {
                let got = await seen.invite
                print(got != nil ? "  ✓ 초대를 받았다 (\(got!.name) → 방 \(got!.room))"
                                 : "  ✗ 초대를 받지 못했다")
                return got != nil
            }

        default:
            print("사용법: --lanprobe host|browse|lobby|relayhost|relayguest|relaylobby"
                  + "|relayinvite [--seconds N]")
            return false
        }
    }

    private actor SeenInvite {
        var invite: (name: String, cid: Int?, room: String)?
        var declinedBy: String?
        var failure: String?
        /// 스냅샷에서 본 사람들의 번호 — 이름이 아니라 번호로 초대해야 한다
        private var cids: [String: Int] = [:]

        func got(from: String, cid: Int?, room: String) { invite = (from, cid, room) }
        func note(_ peers: [RelayLobbySnapshot.Peer]) {
            for p in peers where p.cid != nil { cids[p.name] = p.cid }
        }
        func cidOf(_ name: String) -> Int? { cids[name] }
        /// 회신(거절 또는 전달 실패)이 왔는가
        var settled: Bool { declinedBy != nil || failure != nil }
        func declined(_ who: String) { declinedBy = who }
        func failed(_ why: String) { failure = why }
    }

    private actor SeenLobby {
        var peers: [String] = []
        var rooms: [String] = []
        var updates = 0

        func add(_ snap: RelayLobbySnapshot) {
            updates += 1
            for p in snap.peers where !peers.contains("\(p.name)[\(p.state.ko)]") {
                peers.append("\(p.name)[\(p.state.ko)]")
            }
            for r in snap.rooms where !rooms.contains("\(r.code)/\(r.host)") {
                rooms.append("\(r.code)/\(r.host)")
            }
        }
    }

    /// 콜백이 여러 스레드에서 오므로 결과는 액터에 모은다
    private actor RelayProbeBox {
        var paired = false
        var gotMessage = false
        func sawPeer() { paired = true }
        func sawMessage() { gotMessage = true }
    }

    private actor SeenPeers {
        private var peers: [String: LobbyPeer] = [:]
        var invite: (String, String)?

        func add(_ list: [LobbyPeer]) {
            for p in list { peers[p.id] = p }
        }
        func gotInvite(from: String, room: String) { invite = (from, room) }
        var names: [String] { peers.values.map { "\($0.displayName) [\($0.status.ko)] v\($0.protocolVersion)" }.sorted() }
        var first: LobbyPeer? { peers.values.sorted { $0.id < $1.id }.first }
    }

    private actor SeenRooms {
        var all: [String] = []
        func add(_ rooms: [DiscoveredRoom]) {
            for r in rooms {
                let line = "\(r.name)  방장 \(r.hostName)  v\(r.protocolVersion)  \(r.occupied ? "사용중" : "대기")"
                if !all.contains(line) { all.append(line) }
            }
        }
    }
}
