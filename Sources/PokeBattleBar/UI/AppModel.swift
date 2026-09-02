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

    /// 뷰에서 기술별 상성 배율을 계산하려면 상성표가 필요하다
    private(set) var typeChart: TypeChart?
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
            typeChart = try await PokeAPI.shared.typeChart()
            selectedSlotIDs = Set(roster.prefix(effectiveTeamSize).map(\.id))
            roomName = "\(playerName)의 방"
            status = ""
            screen = .lobby
        } catch {
            errorMessage = describe(error)
            screen = .lobby
        }
    }

    /// 배틀 중에는 네트워크를 기다릴 수 없으므로, 필요한 폼·Z기술·맥스기술을 미리 받아둔다.
    private var megaCache: [String: FormStats] = [:]
    private var gmaxCache: [String: FormStats] = [:]
    private var zMoveCache: [String: MoveDef] = [:]
    private var maxMoveCache: [String: MoveDef] = [:]

    private func preloadForms(for team: [Battler]) async {
        for b in team {
            for f in b.megaForms where megaCache[f] == nil {
                megaCache[f] = try? await PokeAPI.shared.form(named: f)
            }
            if let g = b.gmaxForm, gmaxCache[g] == nil {
                gmaxCache[g] = try? await PokeAPI.shared.form(named: g)
            }
        }
    }

    /// Z기술·맥스기술 정의는 타입별로 고정이라 한 번만 받아두면 된다.
    private func preloadTransformMoves() async {
        guard zMoveCache.isEmpty || maxMoveCache.isEmpty else { return }
        for (_, base) in FormTables.zMoveBase {
            for suffix in ["--physical", "--special"] {
                let n = base + suffix
                if zMoveCache[n] == nil, let m = try? await PokeAPI.shared.move(n) {
                    zMoveCache[n] = m
                }
            }
        }
        for (_, n) in FormTables.maxMove {
            if maxMoveCache[n] == nil, let m = try? await PokeAPI.shared.move(n) {
                maxMoveCache[n] = m
            }
        }
        if let g = try? await PokeAPI.shared.move(FormTables.maxGuard) {
            maxMoveCache[FormTables.maxGuard] = g
        }
    }

    private func installCaches(into e: inout BattleEngine) {
        e.megaCache = megaCache
        e.gmaxCache = gmaxCache
        e.zMoveCache = zMoveCache
        e.maxMoveCache = maxMoveCache
    }

    private func describe(_ e: Error) -> String {
        if (e as NSError).domain == NSCocoaErrorDomain, (e as NSError).code == 260 {
            return "PokeTokenBar 상태 파일을 찾을 수 없습니다. PokeTokenBar 가 설치되어 한 번이라도 실행됐는지 확인해주세요."
        }
        return e.localizedDescription
    }

    // MARK: 팀 구성

    /// 내가 데려갈 수 있는 최대 마리 수 — 보유분과 방 상한 중 작은 쪽.
    var effectiveTeamSize: Int { min(roster.count, rules.maxTeamSize) }

    /// 데려갈 포켓몬. **사용자가 고른 것을 항상 존중한다.**
    /// 예전에는 선택 개수가 정원과 정확히 같지 않으면 선택을 버리고 왼쪽부터 채웠는데,
    /// 그게 "내가 고른 포켓몬이 안 나오고 맨 왼쪽이 나온다"의 원인이었다.
    var teamSlots: [RosterSlot] {
        let picked = roster.filter { selectedSlotIDs.contains($0.id) }
        if picked.isEmpty { return Array(roster.prefix(effectiveTeamSize)) }
        return Array(picked.prefix(rules.maxTeamSize))
    }

    /// 상대에게 **실제로 보낸** 팀. 선봉 선택 화면은 반드시 이걸 보여줘야 한다 —
    /// teamSlots 를 다시 계산해서 보여주면 rules 가 갱신된 뒤 길이가 어긋나고,
    /// 범위를 벗어난 인덱스가 엔진에서 무시되어 activeIndex 가 0 에 남는다.
    var sentTeam: [Battler] { myTeam }

    func toggleSelection(_ slot: RosterSlot) {
        if selectedSlotIDs.contains(slot.id) {
            // 마지막 한 마리는 뺄 수 없다 (팀이 비면 배틀이 안 된다)
            if selectedSlotIDs.count > 1 { selectedSlotIDs.remove(slot.id) }
        } else if selectedSlotIDs.count < rules.maxTeamSize {
            selectedSlotIDs.insert(slot.id)
        }
    }

    /// 방 상한이 줄어들면 선택을 **덮어쓰지 말고 다듬는다** (고른 걸 최대한 유지).
    func trimSelectionToCap() {
        guard selectedSlotIDs.count > rules.maxTeamSize else {
            if selectedSlotIDs.isEmpty {
                selectedSlotIDs = Set(roster.prefix(effectiveTeamSize).map(\.id))
            }
            return
        }
        let keep = roster.filter { selectedSlotIDs.contains($0.id) }.prefix(rules.maxTeamSize)
        selectedSlotIDs = Set(keep.map(\.id))
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
        status = "특수 변신 데이터를 준비하는 중…"
        await preloadForms(for: myTeam)
        await preloadTransformMoves()

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
            guard let chart = typeChart else {
                host.send(.joinRejected(reason: "호스트가 상성표를 아직 불러오지 못했습니다"))
                return
            }
            var e = BattleEngine(state: st, chart: chart, seed: UInt64.random(in: 1...UInt64.max))
            installCaches(into: &e)
            engine = e
            battle = e.state
            // 상대 팀의 메가/거다이맥스 폼도 필요하다 — 받아서 엔진에 다시 심는다
            Task { @MainActor in
                await self.preloadForms(for: guestTeam)
                if var e2 = self.engine {
                    self.installCaches(into: &e2)
                    self.engine = e2
                }
            }
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
        trimSelectionToCap()          // 로비에서 고른 것을 유지한다 (덮어쓰지 않는다)
        myTeam = await buildTeam()
        guard !myTeam.isEmpty else { errorMessage = "팀을 만들 수 없습니다."; return }
        status = "특수 변신 데이터를 준비하는 중…"
        await preloadForms(for: myTeam)
        await preloadTransformMoves()

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
            // 팀은 이미 보냈다. 상한이 더 작아졌으면 호스트가 앞에서 자르므로 우리도 맞춘다.
            rules = r
            if myTeam.count > r.maxTeamSize {
                myTeam = Array(myTeam.prefix(r.maxTeamSize))
            }
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

    /// 이번 턴에 함께 선언할 특수 변신. UI 에서 토글한다.
    var pendingSpecial: SpecialAction?

    func submitMove(_ index: Int) {
        guard let b = battle, case .awaitingMoves = b.phase else { return }
        let special = pendingSpecial
        pendingSpecial = nil
        waitingForOpponent = true
        status = "상대의 기술 선택을 기다리는 중…"
        if role == .host {
            hostPending = .useMove(index: index, special: special)
            maybeResolveTurn()
        } else {
            guestLink?.send(.action(.useMove(index: index, special: special)))
        }
    }

    // MARK: 특수 변신 가능 여부 (UI 에서 버튼 표시에 쓴다)

    /// 지금 나와 있는 포켓몬이 이 변신을 쓸 수 있는가.
    /// 규칙에서 켜져 있고 + 내가 이번 배틀에서 아직 안 썼고 + 그 개체가 자격이 있어야 한다.
    func canUse(_ kind: SpecialKind) -> Bool {
        guard let me = myState, let b = myState?.active else { return false }
        switch kind {
        case .mega:  return rules.allowMega  && !me.usedMega  && b.canMega
        case .gmax:  return rules.allowGmax  && !me.usedGmax  && b.canGmax
        case .zMove: return rules.allowZMove && !me.usedZMove && b.canZMove
        }
    }

    /// 이미 써버린 변신인지 (UI 에서 "사용함" 표시)
    func alreadyUsed(_ kind: SpecialKind) -> Bool {
        guard let me = myState else { return false }
        switch kind {
        case .mega:  return me.usedMega
        case .gmax:  return me.usedGmax
        case .zMove: return me.usedZMove
        }
    }

    func toggleSpecial(_ kind: SpecialKind) {
        guard let b = myState?.active else { return }
        let target: SpecialAction?
        switch kind {
        case .mega:  target = b.megaForms.first.map { SpecialAction.mega(form: $0) }
        case .gmax:  target = .gmax
        case .zMove: target = .zMove
        }
        guard let target else { return }
        // 같은 걸 다시 누르면 해제, 다른 걸 누르면 교체 (한 턴에 하나만)
        if let cur = pendingSpecial, sameKind(cur, target) {
            pendingSpecial = nil
        } else {
            pendingSpecial = target
        }
    }

    /// 리자몽처럼 메가 폼이 둘인 경우 특정 폼을 지정한다.
    func selectMegaForm(_ form: String) {
        pendingSpecial = .mega(form: form)
    }

    /// 뷰가 Z/맥스 변환을 미리 보여주려면 정의가 필요하다
    var zPreview: [String: MoveDef] { zMoveCache.merging(maxMoveCache) { a, _ in a } }

    func kindOf(_ a: SpecialAction) -> SpecialKind {
        switch a {
        case .mega:  .mega
        case .gmax:  .gmax
        case .zMove: .zMove
        }
    }

    func megaFormLabel(_ form: String) -> String {
        megaCache[form]?.suffixLabel ?? (form.hasSuffix("-x") ? "메가 X"
                                        : form.hasSuffix("-y") ? "메가 Y" : "메가")
    }

    private func sameKind(_ a: SpecialAction, _ b: SpecialAction) -> Bool {
        switch (a, b) {
        case (.mega, .mega), (.gmax, .gmax), (.zMove, .zMove): return true
        default: return false
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
