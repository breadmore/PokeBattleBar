import Foundation
import Observation
import Network

enum Screen: Equatable {
    case loading
    case lobby
    case hostingRoom
    case joiningRoom
    case chooseLead
    case battle
    case result
}

enum Role { case none, host, guest }

@MainActor
@Observable
final class AppModel {
    // 내 정보
    var playerName: String = (NSFullUserName().isEmpty ? "트레이너" : NSFullUserName())
    var roster: [RosterSlot] = []
    var rosterSpecies: [Int: SpeciesDef] = [:]
    var selectedSlotIDs: Set<String> = []      // 방 상한을 넘을 때 내가 데려갈 포켓몬

    // 화면 / 상태
    var screen: Screen = .loading
    var role: Role = .none
    var status: String = ""
    var errorMessage: String?

    // 방
    var rules = BattleRules.default
    var roomName: String = ""
    var discovered: [DiscoveredRoom] = []
    var opponentName: String = ""

    // 배틀
    var battle: BattleState?
    var mySide: BattleSide = .host
    var chosenLead: Int?
    var waitingForOpponent = false

    private var chart: TypeChart?
    private var myTeam: [Battler] = []

    private let host = RoomHost()
    private let browser = RoomBrowser()
    private var guestLink: PeerLink?

    private var engine: BattleEngine?
    private var hostPending: BattleAction?
    private var guestPending: BattleAction?
    private var hostLead: Int?
    private var guestLead: Int?

    // MARK: 부팅

    func boot() async {
        screen = .loading
        status = "PokeTokenBar 도감을 읽는 중…"
        do {
            let state = try CompanionStore.load()
            roster = RosterSlot.roster(from: state)
            guard !roster.isEmpty else {
                errorMessage = "PokeTokenBar 에 아직 포켓몬이 없습니다. 동반 포켓몬이 생긴 뒤 다시 열어주세요."
                screen = .lobby
                return
            }
            status = "PokeAPI 에서 종족값·기술을 받는 중… (첫 실행만 오래 걸립니다)"
            for slot in roster {
                rosterSpecies[slot.speciesID] = try await PokeAPI.shared.species(slot.speciesID)
            }
            chart = try await PokeAPI.shared.typeChart()
            selectedSlotIDs = Set(roster.prefix(rules.maxTeamSize).map(\.id))
            roomName = "\(playerName)의 방"
            status = ""
            screen = .lobby
        } catch {
            errorMessage = describe(error)
            screen = .lobby
        }
    }

    private func describe(_ e: Error) -> String {
        if (e as NSError).domain == NSCocoaErrorDomain, (e as NSError).code == 260 {
            return "PokeTokenBar 상태 파일을 찾을 수 없습니다. PokeTokenBar 가 설치되어 한 번이라도 실행됐는지 확인해주세요."
        }
        return e.localizedDescription
    }

    // MARK: 팀 구성

    /// 내가 실제로 데려가는 마리 수 — 보유분과 방 상한 중 작은 쪽.
    var effectiveTeamSize: Int { min(roster.count, rules.maxTeamSize) }

    var teamSlots: [RosterSlot] {
        let picked = roster.filter { selectedSlotIDs.contains($0.id) }
        if picked.count == effectiveTeamSize { return picked }
        return Array(roster.prefix(effectiveTeamSize))
    }

    func toggleSelection(_ slot: RosterSlot) {
        if selectedSlotIDs.contains(slot.id) {
            selectedSlotIDs.remove(slot.id)
        } else if selectedSlotIDs.count < rules.maxTeamSize {
            selectedSlotIDs.insert(slot.id)
        }
    }

    private func buildTeam() async -> [Battler] {
        var out: [Battler] = []
        for slot in teamSlots {
            guard let sp = rosterSpecies[slot.speciesID] else { continue }
            let moves = await MovesetStore.shared.moveset(for: slot, species: sp)
            out.append(Battler.make(slot: slot, species: sp, moves: moves, level: rules.level))
        }
        return out
    }

    func rerollMoves(for slot: RosterSlot) async {
        guard let sp = rosterSpecies[slot.speciesID] else { return }
        _ = await MovesetStore.shared.reroll(for: slot, species: sp)
    }

    func moveset(for slot: RosterSlot) async -> [MoveDef] {
        guard let sp = rosterSpecies[slot.speciesID] else { return [] }
        return await MovesetStore.shared.moveset(for: slot, species: sp)
    }

    // MARK: 방 만들기 (호스트)

    func startHosting() async {
        role = .host
        mySide = .host
        myTeam = await buildTeam()
        guard !myTeam.isEmpty else { errorMessage = "팀을 만들 수 없습니다."; return }

        host.onGuestMessage = { [weak self] msg in
            Task { @MainActor in self?.hostHandle(msg) }
        }
        host.onGuestDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if case .battle = self.screen {
                    self.errorMessage = "상대가 연결을 끊었습니다."
                }
                self.opponentName = ""
                self.battle = nil
                self.engine = nil
                self.screen = .hostingRoom
                self.status = "상대를 기다리는 중…"
            }
        }
        host.onError = { [weak self] e in
            Task { @MainActor in self?.errorMessage = e }
        }

        host.start(roomName: roomName.isEmpty ? "\(playerName)의 방" : roomName,
                   hostName: playerName, rules: rules)
        status = "상대를 기다리는 중…"
        screen = .hostingRoom
    }

    private func hostHandle(_ msg: Wire) {
        switch msg {
        case .join(let name, let team):
            guard !team.isEmpty else {
                host.send(.joinRejected(reason: "상대 팀이 비어 있습니다"))
                return
            }
            opponentName = name
            let guestTeam = Array(team.prefix(rules.maxTeamSize))
            let hostTeam = Array(myTeam.prefix(rules.maxTeamSize))

            let st = BattleState(
                rules: rules,
                sides: [
                    SideState(playerName: playerName, team: hostTeam, activeIndex: 0),
                    SideState(playerName: name, team: guestTeam, activeIndex: 0)
                ]
            )
            guard let chart else {
                host.send(.joinRejected(reason: "호스트가 상성표를 아직 불러오지 못했습니다"))
                return
            }
            engine = BattleEngine(state: st, chart: chart, seed: UInt64.random(in: 1...UInt64.max))
            battle = engine?.state
            host.send(.joinAccepted(rules: rules, hostName: playerName, yourSide: BattleSide.guest.rawValue))
            hostLead = nil; guestLead = nil
            chosenLead = nil
            screen = .chooseLead
            status = "선봉을 고르세요"

        case .chooseLead(let index):
            guestLead = index
            maybeBeginBattle()

        case .action(let a):
            guard let engine else { return }
            switch engine.state.phase {
            case .awaitingMoves:
                guestPending = a
                maybeResolveTurn()
            case .awaitingReplacement(let needs) where needs.contains(BattleSide.guest.rawValue):
                if case .replace(let idx) = a { applyReplacement(.guest, idx) }
            default: break
            }

        case .leave:
            errorMessage = "상대가 방을 나갔습니다."
            resetToLobby()

        default: break
        }
    }

    // MARK: 방 참가 (게스트)

    func startBrowsing() {
        role = .guest
        browser.onRooms = { [weak self] rooms in
            Task { @MainActor in self?.discovered = rooms }
        }
        browser.onError = { [weak self] e in
            Task { @MainActor in self?.errorMessage = e }
        }
        browser.start()
    }

    func stopBrowsing() { browser.stop() }

    /// 자동 매칭 — 비어 있는 첫 방에 바로 들어간다.
    func autoMatch() async {
        guard let room = discovered.first(where: { !$0.occupied }) else {
            errorMessage = "들어갈 수 있는 방이 없습니다. 방을 직접 만들어보세요."
            return
        }
        await join(room)
    }

    func join(_ room: DiscoveredRoom) async {
        role = .guest
        mySide = .guest
        rules.maxTeamSize = room.teamCap
        rules.level = room.level
        selectedSlotIDs = Set(roster.prefix(rules.maxTeamSize).map(\.id))
        myTeam = await buildTeam()
        guard !myTeam.isEmpty else { errorMessage = "팀을 만들 수 없습니다."; return }

        opponentName = room.hostName
        status = "\(room.hostName) 의 방에 접속 중…"
        screen = .joiningRoom

        let link = PeerLink(to: room.endpoint)
        guestLink = link
        let team = myTeam
        let name = playerName
        link.start(
            onMessage: { [weak self] msg in
                Task { @MainActor in self?.guestHandle(msg) }
            },
            onState: { [weak self] st in
                Task { @MainActor in
                    guard let self else { return }
                    switch st {
                    case .ready:
                        link.send(.join(playerName: name, team: team))
                        self.status = "호스트 응답을 기다리는 중…"
                    case .failed(let e):
                        self.errorMessage = "접속 실패: \(e.localizedDescription)"
                        self.resetToLobby()
                    case .cancelled:
                        if self.screen == .battle || self.screen == .chooseLead {
                            self.errorMessage = "호스트와 연결이 끊어졌습니다."
                        }
                        self.resetToLobby()
                    default: break
                    }
                }
            }
        )
    }

    private func guestHandle(_ msg: Wire) {
        switch msg {
        case .joinAccepted(let r, let hostName, let side):
            rules = r
            opponentName = hostName
            mySide = BattleSide(rawValue: side) ?? .guest
            chosenLead = nil
            screen = .chooseLead
            status = "선봉을 고르세요"

        case .joinRejected(let reason):
            errorMessage = reason
            resetToLobby()

        case .battleBegan(let st), .stateChanged(let st):
            battle = st
            applyPhaseToUI(st)

        case .hostLeft:
            errorMessage = "호스트가 방을 닫았습니다."
            resetToLobby()

        default: break
        }
    }

    // MARK: 선봉 / 행동

    func submitLead(_ index: Int) {
        chosenLead = index
        waitingForOpponent = true
        status = "상대의 선봉을 기다리는 중…"
        if role == .host {
            hostLead = index
            maybeBeginBattle()
        } else {
            guestLink?.send(.chooseLead(index: index))
        }
    }

    private func maybeBeginBattle() {
        guard role == .host, var e = engine,
              let h = hostLead, let g = guestLead else { return }
        e.setLead(.host, index: h)
        e.setLead(.guest, index: g)
        e.beginBattle()
        engine = e
        battle = e.state
        host.send(.battleBegan(state: e.state))
        waitingForOpponent = false
        applyPhaseToUI(e.state)
    }

    func submitMove(_ index: Int) {
        guard let b = battle, case .awaitingMoves = b.phase else { return }
        waitingForOpponent = true
        status = "상대의 기술 선택을 기다리는 중…"
        if role == .host {
            hostPending = .useMove(index: index)
            maybeResolveTurn()
        } else {
            guestLink?.send(.action(.useMove(index: index)))
        }
    }

    func submitReplacement(_ teamIndex: Int) {
        guard let b = battle, case .awaitingReplacement = b.phase else { return }
        if role == .host {
            applyReplacement(.host, teamIndex)
        } else {
            guestLink?.send(.action(.replace(teamIndex: teamIndex)))
            waitingForOpponent = true
            status = "진행을 기다리는 중…"
        }
    }

    private func maybeResolveTurn() {
        guard role == .host, var e = engine,
              let h = hostPending, let g = guestPending else { return }
        hostPending = nil; guestPending = nil
        e.resolveTurn(hostAction: h, guestAction: g)
        engine = e
        battle = e.state
        host.send(.stateChanged(state: e.state))
        waitingForOpponent = false
        applyPhaseToUI(e.state)
    }

    private func applyReplacement(_ side: BattleSide, _ idx: Int) {
        guard role == .host, var e = engine else { return }
        e.applyReplacement(side, teamIndex: idx)
        engine = e
        battle = e.state
        host.send(.stateChanged(state: e.state))
        waitingForOpponent = false
        applyPhaseToUI(e.state)
    }

    private func applyPhaseToUI(_ st: BattleState) {
        switch st.phase {
        case .chooseLead:
            screen = .chooseLead
            status = "선봉을 고르세요"
        case .awaitingMoves:
            screen = .battle
            waitingForOpponent = false
            status = "기술을 고르세요"
        case .awaitingReplacement(let needs):
            screen = .battle
            if needs.contains(mySide.rawValue) {
                waitingForOpponent = false
                status = "다음 포켓몬을 고르세요"
            } else {
                waitingForOpponent = true
                status = "상대가 다음 포켓몬을 고르는 중…"
            }
        case .finished:
            screen = .result
            status = ""
        }
    }

    // MARK: 편의

    var myState: SideState? { battle?.sides[mySide.rawValue] }
    var foeState: SideState? { battle?.sides[mySide.other.rawValue] }

    var needsMyReplacement: Bool {
        guard let b = battle, case .awaitingReplacement(let needs) = b.phase else { return false }
        return needs.contains(mySide.rawValue)
    }

    var resultText: String {
        guard let b = battle, case .finished(let w) = b.phase else { return "" }
        guard let w else { return "무승부" }
        return w == mySide.rawValue ? "승리!" : "패배…"
    }

    func resetToLobby() {
        host.stop()
        guestLink?.cancel()
        guestLink = nil
        engine = nil
        battle = nil
        hostPending = nil; guestPending = nil
        hostLead = nil; guestLead = nil
        chosenLead = nil
        waitingForOpponent = false
        role = .none
        status = ""
        screen = .lobby
    }

    func leaveEverything() {
        if role == .host { host.send(.hostLeft) }
        if role == .guest { guestLink?.send(.leave) }
        resetToLobby()
    }
}
