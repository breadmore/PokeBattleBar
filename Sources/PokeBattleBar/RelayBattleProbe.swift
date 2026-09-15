import Foundation
import Network

/// **중계 서버로 배틀이 끝까지 되는가.**
///
/// 기존 진단(--lanprobe relayhost)은 짝이 맞고 채팅 한 통이 오가는 것까지만
/// 봤다. 그런데 정작 중요한 것은 **배틀이 끝까지 중계되는가** 다 —
/// 팀 전송(수십 KB), 선봉 선택, 턴 주고받기, 승패까지.
///
/// 큰 프레임은 쪼개져 도착하고 중계기는 바이트를 그대로 흘리기만 한다.
/// 그 조립이 틀리면 **핸드셰이크는 멀쩡한데 배틀만 멈춘다** — 짧은 채팅
/// 한 통으로는 절대 드러나지 않는 종류의 고장이다.
///
///     python3 scripts/relay.py --secret S
///     POKEBATTLE_RELAY=1.2.3.4 POKEBATTLE_ROOM=B1 POKEBATTLE_RELAY_SECRET=S \
///       PokeBattleBar --relaybattle host  --seconds 40
///     POKEBATTLE_RELAY=1.2.3.4 POKEBATTLE_ROOM=B1 POKEBATTLE_RELAY_SECRET=S \
///       PokeBattleBar --relaybattle guest --seconds 35
@MainActor
enum RelayBattleProbe {

    static func run(role: String, seconds: Int) async -> Bool {
        let env = ProcessInfo.processInfo.environment
        let addr = env["POKEBATTLE_RELAY"] ?? "127.0.0.1"
        let room = RelayConfig.normalize(room: env["POKEBATTLE_ROOM"] ?? "BATTLE1")
        let secret = env["POKEBATTLE_RELAY_SECRET"]
        let tag = role == "host" ? "호스트" : "게스트"

        guard let endpoint = DirectConnect.endpoint(from: addr,
                                                    defaultPort: RelayConfig.defaultPort) else {
            print("  ✗ 중계 주소를 알아볼 수 없습니다: \(addr)")
            return false
        }
        guard let team = await makeTeam(role == "host" ? [143, 94] : [130, 65]) else {
            print("  ✗ 팀을 만들 수 없습니다")
            return false
        }
        print("[\(tag)] 팀 준비: \(team.map(\.name).joined(separator: ", "))")

        let box = ProbeState()
        if role == "host" {
            guard let chart = try? await PokeAPI.shared.typeChart() else {
                print("  ✗ 상성표를 불러올 수 없습니다")
                return false
            }
            await runHost(endpoint: endpoint, room: room, secret: secret,
                          team: team, chart: chart, box: box, seconds: seconds, tag: tag)
        } else {
            await runGuest(endpoint: endpoint, room: room, secret: secret,
                           team: team, box: box, seconds: seconds, tag: tag)
        }

        let s = box.snapshot()
        print("")
        var ok = true
        ok = show(s.paired, "중계로 짝이 맞았다") && ok
        ok = show(s.teamCount > 0, "팀이 오갔다 (수십 KB 프레임)",
                  "상대 팀 \(s.teamCount)마리") && ok
        ok = show(s.began, "배틀이 시작됐다") && ok
        ok = show(s.turns > 0, "턴이 오갔다", "\(s.turns)턴") && ok
        ok = show(s.done, "승패가 났다", s.result) && ok
        return ok
    }

    // MARK: 호스트 — 엔진을 돌린다 (권위는 계속 호스트에 있다)

    private static func runHost(endpoint: NWEndpoint, room: String, secret: String?,
                                team: [Battler], chart: TypeChart,
                                box: ProbeState, seconds: Int, tag: String) async {
        let host = RoomHost()
        let state = HostState(myTeam: team, chart: chart)

        host.onError = { print("  ✗ \($0)") }
        host.onRelayRegistered = { print("[\(tag)] 방 등록됨 — 코드 \(room)") }
        host.onGuestConnected = { _ in
            Task { @MainActor in
                print("[\(tag)] 짝 성사")
                box.paired = true
            }
        }
        host.onGuestMessage = { msg in
            Task { @MainActor in
                handleHost(msg, host: host, s: state, box: box, tag: tag)
            }
        }
        host.startRelay(server: endpoint, room: room, secret: secret,
                        hostName: "relaybattle-host", rules: .default, modeSummary: "진단")
        print("[\(tag)] 중계 서버에 방 \(room) 등록 — \(seconds)초 기다립니다")
        try? await Task.sleep(for: .seconds(seconds))
        host.stop()
    }

    private static func handleHost(_ msg: Wire, host: RoomHost,
                                   s: HostState, box: ProbeState, tag: String) {
        switch msg {
        case .join(let name, let foeTeam):
            print("[\(tag)] 팀 수신: \(name) — \(foeTeam.count)마리")
            box.teamCount = foeTeam.count
            var st = BattleState(rules: .default,
                                 sides: [SideState(playerName: "host", team: s.myTeam,
                                                   activeIndex: 0),
                                         SideState(playerName: name, team: foeTeam,
                                                   activeIndex: 0)])
            st.phase = .chooseLead
            s.engine = BattleEngine(state: st, chart: s.chart, seed: 7)
            host.send(.joinAccepted(rules: .default, hostName: "relaybattle-host", yourSide: 1))

        case .chooseLead(let index):
            guard var e = s.engine, !s.began else { return }
            e.setLead(.host, index: 0)
            e.setLead(.guest, index: index)
            e.beginBattle()
            s.engine = e
            s.began = true
            box.began = true
            print("[\(tag)] 선봉 확정 — 배틀 시작")
            host.send(.battleBegan(state: e.state))

        case .action(let a):
            guard var e = s.engine else { return }
            guard case .awaitingMoves = e.state.phase else {
                // 쓰러진 뒤 교체를 기다리는 중이면 그것만 처리한다
                if case .awaitingReplacement(let needs) = e.state.phase,
                   needs.contains(BattleSide.guest.rawValue),
                   case .replace(let idx) = a {
                    e.applyReplacement(.guest, teamIndex: idx)
                    s.engine = e
                    host.send(.stateChanged(state: e.state))
                }
                return
            }
            // 호스트도 같은 기술을 낸다 — 무엇이 오갔는지가 관심사다
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: a)
            s.engine = e
            box.turns += 1
            host.send(.stateChanged(state: e.state))
            // 호스트가 쓰러졌으면 바로 다음을 낸다 (진단이 멈추지 않게)
            if case .awaitingReplacement(let needs) = e.state.phase,
               needs.contains(BattleSide.host.rawValue) {
                let alive = e.state.sides[0].team.firstIndex { !$0.isFainted }
                if let alive {
                    e.applyReplacement(.host, teamIndex: alive)
                    s.engine = e
                    host.send(.stateChanged(state: e.state))
                }
            }
            if case .finished(let w) = e.state.phase {
                box.finish(w == nil ? "무승부" : (w == 0 ? "호스트 승" : "게스트 승"))
                print("[\(tag)] 배틀 종료 — \(e.state.turn)턴")
            }

        default:
            break
        }
    }

    // MARK: 게스트 — 받은 상태에 맞춰 행동한다

    private static func runGuest(endpoint: NWEndpoint, room: String, secret: String?,
                                 team: [Battler], box: ProbeState,
                                 seconds: Int, tag: String) async {
        let link = PeerLink(to: endpoint)
        link.startRelay(
            hello: RelayHello(role: .guest, room: room, name: "relaybattle-guest",
                              secret: secret),
            onRegistered: { _ in },
            onPaired: { _ in
                Task { @MainActor in
                    print("[\(tag)] 짝 성사 — 팀을 보냅니다 (\(team.count)마리)")
                    box.paired = true
                    link.send(.join(playerName: "relaybattle-guest", team: team))
                }
            },
            onRejected: { why in print("  ✗ 거절: \(why)") },
            onMessage: { msg in
                Task { @MainActor in handleGuest(msg, link: link, box: box, tag: tag) }
            },
            onState: { st in
                if case .failed(let e) = st { print("  ✗ 접속 실패: \(e)") }
            }
        )
        print("[\(tag)] 중계 서버의 방 \(room) 에 참가 — \(seconds)초")
        try? await Task.sleep(for: .seconds(seconds))
        link.cancel()
    }

    private static func handleGuest(_ msg: Wire, link: PeerLink,
                                    box: ProbeState, tag: String) {
        switch msg {
        case .joinAccepted:
            print("[\(tag)] 참가 승인 — 선봉을 고릅니다")
            link.send(.chooseLead(index: 0))

        case .battleBegan(let st):
            box.began = true
            box.teamCount = st.sides[0].team.count
            print("[\(tag)] 배틀 시작 — 상대 \(st.sides[0].team.count)마리")
            act(on: st, link: link, box: box, tag: tag)

        case .stateChanged(let st):
            act(on: st, link: link, box: box, tag: tag)

        case .joinRejected(let why):
            print("  ✗ 참가 거절: \(why)")

        default:
            break
        }
    }

    private static func act(on st: BattleState, link: PeerLink,
                            box: ProbeState, tag: String) {
        switch st.phase {
        case .awaitingMoves:
            box.turns += 1
            link.send(.action(.useMove(index: 0)))
        case .awaitingReplacement(let needs):
            if needs.contains(BattleSide.guest.rawValue),
               let alive = st.sides[1].team.firstIndex(where: { !$0.isFainted }) {
                link.send(.action(.replace(teamIndex: alive)))
            }
        case .finished(let w):
            box.finish(w == nil ? "무승부" : (w == 0 ? "호스트 승" : "게스트 승"))
            print("[\(tag)] 배틀 종료 — \(st.turn)턴")
        default:
            break
        }
    }

    // MARK: 도우미

    private static func makeTeam(_ ids: [Int]) async -> [Battler]? {
        var out: [Battler] = []
        for id in ids {
            guard let sp = try? await PokeAPI.shared.species(id) else { return nil }
            var moves: [MoveDef] = []
            for n in ["tackle", "growl"] {
                if let m = try? await PokeAPI.shared.move(n) { moves.append(m) }
            }
            guard !moves.isEmpty else { return nil }
            let slot = RosterSlot(id: "p\(id)", speciesID: id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            out.append(Battler.make(slot: slot, species: sp, moves: moves, level: 50))
        }
        return out
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }
}

/// 호스트 쪽 진행 상태 (엔진은 여기 한 곳에서만 만진다)
@MainActor
final class HostState {
    let myTeam: [Battler]
    let chart: TypeChart
    var engine: BattleEngine?
    var began = false

    init(myTeam: [Battler], chart: TypeChart) {
        self.myTeam = myTeam
        self.chart = chart
    }
}

/// 진단이 본 것들
@MainActor
final class ProbeState {
    var paired = false
    var teamCount = 0
    var began = false
    var turns = 0
    private var isDone = false
    private var resultText = ""

    func finish(_ r: String) {
        guard !isDone else { return }
        isDone = true
        resultText = r
    }

    func snapshot() -> (paired: Bool, teamCount: Int, began: Bool,
                        turns: Int, done: Bool, result: String) {
        (paired, teamCount, began, turns, isDone, resultText)
    }
}
