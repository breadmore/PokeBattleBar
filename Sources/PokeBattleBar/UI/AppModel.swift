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
    /// 방 목록에 보여줄 모드 요약
    var modeSummary: String {
        if rules.metronomeMode { return "토게피 손가락흔들기" }
        var tags: [String] = []
        if rules.randomMoveset { tags.append("랜덤기술") }
        if rules.autoMove { tags.append("자유의지") }
        if rules.autoSpecial { tags.append("자동변신") }
        return tags.isEmpty ? "일반" : tags.joined(separator: "·")
    }

    /// 표시용 앱 버전 (번들에서 읽는다)
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    var protocolVersion: Int { PokeBattleProtocol.version }

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

    // 채팅
    struct ChatLine: Identifiable, Sendable {
        let id = UUID()
        var from: String
        var text: String
        var mine: Bool
    }
    var chatLines: [ChatLine] = []
    var chatDraft: String = ""

    // 전적 / 포인트
    var record = RecordStore.Record()
    var lastPointsGained: Int?

    // MARK: 턴 재생 (실제 배틀처럼 순서대로 보여준다)
    //
    // 엔진은 한 턴을 한 번에 계산한다. 그 결과만 그리면 누가 먼저 때렸는지,
    // 무슨 일이 있었는지 알 수 없다. 그래서 엔진이 남긴 단계(steps) 를
    // 하나씩 재생하면서 HP·로그를 점진적으로 보여준다.

    /// 재생 중 화면에 그릴 HP (없으면 실제 상태를 쓴다)
    var playbackHostHP: [Int]?
    var playbackGuestHP: [Int]?
    var playbackHostActive: Int?
    var playbackGuestActive: Int?
    /// 재생 중 보여줄 로그 줄 수
    var playbackLogCount: Int?
    /// 재생 중인가 (행동 입력을 막는다)
    var isPlayingBack = false
    /// 지금 재생 중인 단계 설명 (상단 배너)
    var playbackBanner: String?

    private var playbackTask: Task<Void, Never>?

    /// 한 단계당 머무는 시간
    private let stepDuration: Duration = .milliseconds(850)

    /// 엔진이 넘겨준 단계들을 순서대로 재생한다.
    private func playback(_ st: BattleState) {
        playbackTask?.cancel()
        guard !st.steps.isEmpty else {
            clearPlayback()
            return
        }
        isPlayingBack = true
        // 재생은 턴 시작 시점부터 — 로그는 이번 턴 이전까지만 보여준다
        let addedLines = st.steps.reduce(0) { $0 + $1.log.count }
        var shown = max(0, st.log.count - addedLines)
        playbackLogCount = shown

        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in st.steps {
                if Task.isCancelled { return }
                shown += step.log.count
                // 애니메이션은 뷰가 값 변화를 보고 처리한다 (HPBar 의 .animation)
                self.playbackHostHP = step.hostHP
                self.playbackGuestHP = step.guestHP
                self.playbackHostActive = step.hostActive
                self.playbackGuestActive = step.guestActive
                self.playbackLogCount = shown
                // 이 단계의 첫 줄을 배너로 (누가 무엇을 했는지)
                self.playbackBanner = step.log.first
                try? await Task.sleep(for: self.stepDuration)
            }
            if Task.isCancelled { return }
            self.clearPlayback()
            // 재생이 끝난 뒤에 다음 단계 UI 를 연다
            self.applyPhaseToUI(st)
            if self.rules.autoMove { self.advanceAutoIfNeeded() }
        }
    }

    private func clearPlayback() {
        playbackHostHP = nil
        playbackGuestHP = nil
        playbackHostActive = nil
        playbackGuestActive = nil
        playbackLogCount = nil
        playbackBanner = nil
        isPlayingBack = false
    }

    /// 화면에 그릴 팀 (재생 중이면 그 시점 HP 로 덮어쓴다)
    func displayTeam(_ side: BattleSide) -> [Battler] {
        guard let b = battle else { return [] }
        var team = b.sides[side.rawValue].team
        let hp = side == .host ? playbackHostHP : playbackGuestHP
        if let hp {
            for i in team.indices where i < hp.count { team[i].currentHP = hp[i] }
        }
        return team
    }

    func displayActiveIndex(_ side: BattleSide) -> Int {
        let live = battle?.sides[side.rawValue].activeIndex ?? 0
        let pb = side == .host ? playbackHostActive : playbackGuestActive
        return pb ?? live
    }

    /// 화면에 그릴 로그
    var displayLog: [String] {
        guard let b = battle else { return [] }
        guard let n = playbackLogCount else { return b.log }
        return Array(b.log.prefix(n))
    }

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
            status = "도구·특성 데이터를 받는 중…"
            await loadLoadoutOptions()
            record = await RecordStore.shared.record
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
        e.metronomePool = metronomePool
        e.formCache = formCache
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

    /// 토게피 손가락흔들기 모드의 팀.
    /// 보유 여부와 무관하게 양쪽 모두 토게피 1마리, 기술은 손가락흔들기 하나,
    /// PP 최대치, 생명의구슬 장착으로 고정한다.
    private func buildMetronomeTeam() async -> [Battler] {
        guard let sp = try? await PokeAPI.shared.species(GameModes.Metronome.speciesID),
              var mv = try? await PokeAPI.shared.move(GameModes.Metronome.move) else { return [] }
        mv.pp = GameModes.maxPP(base: mv.pp)
        let item = await ItemCatalog.shared.item(GameModes.Metronome.item)
        let slot = RosterSlot(id: "metronome-togepi", speciesID: sp.id,
                              nature: GameModes.Metronome.nature, rarity: "common",
                              isShiny: false, origin: .dex, fullyEvolved: true)
        var b = Battler.make(slot: slot, species: sp, moves: [mv], level: rules.level,
                             heldItem: item, ability: nil)
        b.moves[0].ppLeft = mv.pp
        return [b]
    }

    /// 손가락흔들기 풀을 받아둔다 (첫 실행만 오래 걸린다).
    private var metronomePool: [MoveDef] = []
    /// 토게피 모드용 고정 팀 (양쪽에 그대로 쓴다)
    private var metronomeTeamSnapshot: [Battler] = []
    private func preloadMetronomePool() async {
        guard metronomePool.isEmpty else { return }
        var out: [MoveDef] = []
        let names = GameModes.uniquePool
        for (i, n) in names.enumerated() {
            if let m = try? await PokeAPI.shared.move(n) { out.append(m) }
            if i % 20 == 0 {
                status = "손가락흔들기 기술 풀 준비 중… \(i)/\(names.count)"
            }
        }
        metronomePool = out
    }

    private func buildTeam() async -> [Battler] {
        // 토게피 모드는 로스터와 무관하게 고정 팀을 쓴다
        if rules.metronomeMode { return await buildMetronomeTeam() }
        var out: [Battler] = []
        for slot in teamSlots {
            guard let sp = rosterSpecies[slot.speciesID] else { continue }
            // 랜덤 기술 모드면 배틀마다 새로 뽑는다 (저장본을 덮지 않는 일회성 추첨)
            let moves = rules.randomMoveset
                ? await MovesetStore.shared.drawWithoutSaving(species: sp)
                : await MovesetStore.shared.moveset(for: slot, species: sp)
            let (item, ability) = await LoadoutStore.shared.resolve(for: slot, species: sp)
            // 고른 폼이 있으면 그 종족값·타입으로 만든다
            let formName = await LoadoutStore.shared.loadout(for: slot).form
            var formStats: FormStats?
            if let formName {
                if formCache[formName] == nil {
                    formCache[formName] = try? await PokeAPI.shared.form(named: formName)
                }
                formStats = formCache[formName]
            }
            out.append(Battler.make(slot: slot, species: sp, moves: moves,
                                    level: rules.level, heldItem: item, ability: ability,
                                    form: formStats, formName: formName))
        }
        return out
    }

    // MARK: 도구 / 특성 선택

    var itemsForSpecies: [Int: [ItemDef]] = [:]
    var abilitiesForSpecies: [Int: [AbilityDef]] = [:]
    var loadouts: [String: LoadoutStore.Loadout] = [:]
    /// 개체별 기술 — Z크리스탈이 실제로 쓸 수 있는지 즉시 판정하려면 필요하다
    var movesetsBySlot: [String: [MoveDef]] = [:]

    /// 로비에서 도구·특성을 고를 수 있도록 목록을 미리 받아둔다.
    private func loadLoadoutOptions() async {
        await ItemCatalog.shared.loadAll()
        for slot in roster {
            guard let sp = rosterSpecies[slot.speciesID] else { continue }
            if itemsForSpecies[slot.speciesID] == nil {
                itemsForSpecies[slot.speciesID] = await ItemCatalog.shared.available(forSpecies: sp)
            }
            if abilitiesForSpecies[slot.speciesID] == nil {
                abilitiesForSpecies[slot.speciesID] = await AbilityCatalog.shared.abilities(for: sp)
            }
            loadouts[slot.id] = await LoadoutStore.shared.loadout(for: slot)
            movesetsBySlot[slot.id] = await MovesetStore.shared.moveset(for: slot, species: sp)
        }
    }

    /// 끼운 도구가 **이 개체에게 실제로 작동하는지** 판정한다.
    /// 메가스톤·다이버섯·Z크리스탈은 개체 자격에 따라 무용지물이 될 수 있어서,
    /// 로비에서 미리 알려줘야 배틀에서 헛클릭하지 않는다.
    func itemReadiness(for slot: RosterSlot) -> ItemReadiness? {
        guard let item = currentItem(for: slot) else { return nil }
        guard let sp = rosterSpecies[slot.speciesID] else {
            return ItemReadiness(ok: false, headline: "확인 불가", detail: "종 데이터 없음")
        }
        let moves = movesetsBySlot[slot.id] ?? []

        switch item.kind {
        case .megaStone(let form):
            guard sp.megaForms.contains(form) else {
                return ItemReadiness(ok: false, headline: "메가진화 불가",
                                     detail: "\(sp.display)의 스톤이 아닙니다")
            }
            let label = form.hasSuffix("-x") ? "메가 X" : (form.hasSuffix("-y") ? "메가 Y" : "메가")
            return ItemReadiness(ok: true, headline: "메가진화 가능",
                                 detail: "\(label) 로 진화")

        case .dynamaxBand:
            return ItemReadiness(ok: true, headline: "다이맥스 가능",
                                 detail: "일반 다이맥스 전용 (거다이맥스는 다이버섯)")

        case .maxMushroom:
            guard sp.canGigantamax else {
                return ItemReadiness(ok: false, headline: "거다이맥스 불가",
                                     detail: "\(sp.display)는 거다이맥스 폼이 없습니다")
            }
            return ItemReadiness(ok: true, headline: "거다이맥스 가능",
                                 detail: "전용기 " + (GMaxMove.forSpecies(sp.id)?.ko ?? "있음"))

        case .zCrystalType(let t):
            let match = moves.filter {
                $0.damageClass != .status && $0.isDamaging && $0.type == t
            }
            guard !match.isEmpty else {
                return ItemReadiness(ok: false, headline: "Z기술 불가",
                                     detail: "\(t.ko)타입 공격기가 없습니다")
            }
            return ItemReadiness(ok: true, headline: "Z기술 가능",
                                 detail: match.map(\.display).joined(separator: ", "))

        case .zCrystalSignature(let sid):
            guard sid == sp.id else {
                return ItemReadiness(ok: false, headline: "Z기술 불가",
                                     detail: "\(sp.display) 전용이 아닙니다")
            }
            let atk = moves.filter { $0.damageClass != .status && $0.isDamaging }
            guard !atk.isEmpty else {
                return ItemReadiness(ok: false, headline: "Z기술 불가",
                                     detail: "공격기가 없습니다")
            }
            return ItemReadiness(ok: true, headline: "전용 Z기술 가능",
                                 detail: "타입 제한 없음")

        default:
            return ItemReadiness(ok: true, headline: "상시 효과",
                                 detail: item.shortEffect.isEmpty ? item.display : item.shortEffect)
        }
    }

    /// 로비에서 띄울 장비 경고.
    /// 변신은 **종류별로 배틀당 1회**뿐이라, 같은 슬롯을 노리는 도구를 여러 마리가 끼면
    /// 한 쪽은 반드시 낭비된다. 배틀에 들어가기 전에 알려줘야 한다.
    var loadoutWarnings: [LoadoutWarning] {
        var out: [LoadoutWarning] = []
        let team = teamSlots

        func name(_ slot: RosterSlot) -> String {
            rosterSpecies[slot.speciesID]?.display ?? "#\(slot.speciesID)"
        }

        // 슬롯별로 "실제로 작동하는" 도구를 낀 개체를 센다.
        // 작동하지 않는 도구는 슬롯 경쟁이 아니라 낭비 경고로 따로 잡는다.
        var mega: [String] = []
        var dynamax: [(String, String)] = []      // (포켓몬, 도구)
        var zMove: [String] = []
        var broken: [(String, String, String)] = []   // (포켓몬, 도구, 이유)

        for slot in team {
            guard let item = currentItem(for: slot) else { continue }
            let r = itemReadiness(for: slot)
            guard let r else { continue }
            if !r.ok {
                broken.append((name(slot), item.display, r.detail))
                continue
            }
            switch item.kind {
            case .megaStone:                        mega.append(name(slot))
            case .dynamaxBand:                      dynamax.append((name(slot), item.display))
            case .maxMushroom:                      dynamax.append((name(slot), item.display))
            case .zCrystalType, .zCrystalSignature: zMove.append(name(slot))
            default: break
            }
        }

        if dynamax.count > 1 {
            let list = dynamax.map { "\($0.0)(\($0.1))" }.joined(separator: ", ")
            out.append(LoadoutWarning(
                id: "dynamax",
                severity: .redundant,
                title: "다이맥스 도구를 \(dynamax.count)마리가 끼고 있습니다",
                detail: "다이맥스와 거다이맥스는 같은 슬롯이라 **배틀당 한 번**뿐입니다. "
                      + "먼저 쓴 쪽만 발동하고 나머지는 낭비됩니다 — \(list)"))
        }
        if mega.count > 1 {
            out.append(LoadoutWarning(
                id: "mega",
                severity: .redundant,
                title: "메가스톤을 \(mega.count)마리가 끼고 있습니다",
                detail: "메가진화는 배틀당 한 번뿐입니다 — \(mega.joined(separator: ", "))"))
        }
        if zMove.count > 1 {
            out.append(LoadoutWarning(
                id: "z",
                severity: .redundant,
                title: "Z크리스탈을 \(zMove.count)마리가 끼고 있습니다",
                detail: "Z기술은 배틀당 한 번뿐입니다 — \(zMove.joined(separator: ", "))"))
        }
        for (who, item, why) in broken {
            out.append(LoadoutWarning(
                id: "broken-\(who)-\(item)",
                severity: .waste,
                title: "\(who)의 \(item)은 작동하지 않습니다",
                detail: why))
        }
        return out
    }

    /// 같은 도구를 다른 개체가 이미 끼고 있는지 (중복 안내용)
    func slotsSharingItem(_ slot: RosterSlot) -> [String] {
        guard let name = loadouts[slot.id]?.item else { return [] }
        return roster.compactMap { other in
            guard other.id != slot.id, loadouts[other.id]?.item == name else { return nil }
            return rosterSpecies[other.speciesID]?.display ?? "#\(other.speciesID)"
        }
    }

    func setItem(_ item: ItemDef?, for slot: RosterSlot) async {
        await LoadoutStore.shared.setItem(item?.name, for: slot)
        loadouts[slot.id] = await LoadoutStore.shared.loadout(for: slot)
        if movesetsBySlot[slot.id] == nil, let sp = rosterSpecies[slot.speciesID] {
            movesetsBySlot[slot.id] = await MovesetStore.shared.moveset(for: slot, species: sp)
        }
    }

    func setAbility(_ ability: AbilityDef?, for slot: RosterSlot) async {
        await LoadoutStore.shared.setAbility(ability?.name, for: slot)
        loadouts[slot.id] = await LoadoutStore.shared.loadout(for: slot)
    }

    func currentItem(for slot: RosterSlot) -> ItemDef? {
        guard let n = loadouts[slot.id]?.item else { return nil }
        return itemsForSpecies[slot.speciesID]?.first { $0.name == n }
    }

    // MARK: 폼 선택 (PokeTokenBar 는 건드리지 않는다)

    /// 이 개체가 고를 수 있는 폼 (로토무 히트 등). 없으면 빈 배열.
    func selectableForms(for slot: RosterSlot) -> [String] {
        guard let sp = rosterSpecies[slot.speciesID] else { return [] }
        return FormChange.selectable(for: sp)
    }

    /// 지금 고른 폼
    func currentForm(for slot: RosterSlot) -> String? {
        loadouts[slot.id]?.form
    }

    func setForm(_ form: String?, for slot: RosterSlot) async {
        await LoadoutStore.shared.setForm(form, for: slot)
        loadouts[slot.id] = await LoadoutStore.shared.loadout(for: slot)
        if let form, formCache[form] == nil {
            formCache[form] = try? await PokeAPI.shared.form(named: form)
        }
    }

    /// 폼 종족값 캐시 (배틀 팀 구성에 필요)
    private var formCache: [String: FormStats] = [:]

    /// 배틀 중 자동 변신에 필요한 폼들을 미리 받아둔다
    private func preloadAutoForms(for team: [Battler]) async {
        for b in team {
            guard let ab = b.ability?.name,
                  let rule = FormChange.autoRule(ability: ab, speciesID: b.speciesID) else { continue }
            var names: [String] = []
            switch rule {
            case .byWeather(let map, let base): names = Array(map.values) + [base]
            case .inSun(let f, let base):       names = [f, base]
            case .belowHP(_, let f, let base):  names = [f, base]
            case .aboveHP(_, let f, let base):  names = [f, base]
            }
            for n in names where formCache[n] == nil {
                formCache[n] = try? await PokeAPI.shared.form(named: n)
            }
        }
    }

    func currentAbility(for slot: RosterSlot) -> AbilityDef? {
        let opts = abilitiesForSpecies[slot.speciesID] ?? []
        if let n = loadouts[slot.id]?.ability, let a = opts.first(where: { $0.name == n }) { return a }
        return opts.first { !$0.isHidden } ?? opts.first
    }

    func rerollMoves(for slot: RosterSlot) async {
        guard let sp = rosterSpecies[slot.speciesID] else { return }
        let fresh = await MovesetStore.shared.reroll(for: slot, species: sp)
        // Z크리스탈 사용 가능 여부가 기술에 달려 있으므로 함께 갱신한다
        movesetsBySlot[slot.id] = fresh
    }

    // MARK: 기술 직접 선택 (1번)

    /// 이 개체가 배울 수 있는 기술 목록. 실전에서 쓸 수 없는 것(Showdown 기준)은 뺀다.
    func learnableMoves(for slot: RosterSlot) -> [String] {
        guard let sp = rosterSpecies[slot.speciesID] else { return [] }
        return sp.learnableMoves.filter { name in
            guard let m = Showdown.move(name) else { return true }   // 모르면 일단 허용
            return m.isUsable
        }.sorted()
    }

    func setMoves(_ names: [String], for slot: RosterSlot) async {
        let fresh = await MovesetStore.shared.setMoves(names, for: slot)
        movesetsBySlot[slot.id] = fresh
    }

    // MARK: 추천 세팅 (6번)

    /// 실전에서 많이 쓰이는 기술·도구·특성이 있는가
    func hasRecommendation(for slot: RosterSlot) -> Bool {
        guard let sp = rosterSpecies[slot.speciesID] else { return false }
        return Showdown.set(forSpeciesName: sp.name) != nil
    }

    /// 추천이 없는 이유. 버튼이 그냥 안 보이면 왜 없는지 알 수 없다.
    func recommendationUnavailableReason(for slot: RosterSlot) -> String? {
        guard let sp = rosterSpecies[slot.speciesID] else { return nil }
        if Showdown.set(forSpeciesName: sp.name) != nil { return nil }
        // 원본은 9세대 랜덤배틀 세팅이라, 9세대에 없거나 미진화면 빠져 있다
        if !slot.fullyEvolved { return "아직 진화가 끝나지 않았습니다" }
        if sp.id > 1025 { return "실전 세팅 데이터에 없는 종입니다" }
        return "9세대에 등장하지 않거나 미진화 종이라 실전 세팅이 없습니다"
    }

    /// 추천 특성 이름들 (그 종이 실제로 가질 수 있는 것만)
    func recommendedAbilityNames(for slot: RosterSlot) -> [String] {
        guard let sp = rosterSpecies[slot.speciesID],
              let rec = Showdown.set(forSpeciesName: sp.name) else { return [] }
        let owned = Set((abilitiesForSpecies[slot.speciesID] ?? []).map(\.name))
        return rec.abilities.filter { owned.contains($0) }
    }

    /// 추천 도구 이름 (그 종에게 노출되는 것만)
    func recommendedItemName(for slot: RosterSlot) -> String? {
        guard let sp = rosterSpecies[slot.speciesID],
              let rec = Showdown.set(forSpeciesName: sp.name),
              let want = rec.item else { return nil }
        let avail = itemsForSpecies[slot.speciesID] ?? []
        return avail.contains { $0.name == want } ? want : nil
    }

    /// 추천 기술 이름들 (그 개체가 배울 수 있는 것만)
    func recommendedMoveNames(for slot: RosterSlot) -> [String] {
        guard let sp = rosterSpecies[slot.speciesID],
              let rec = Showdown.set(forSpeciesName: sp.name) else { return [] }
        let learnable = Set(sp.learnableMoves)
        return rec.movePool.filter { learnable.contains($0) }
    }

    /// Showdown 의 실전 세팅을 그대로 적용한다.
    /// 포켓몬을 잘 모르는 사람도 바로 쓸 수 있게 하기 위한 기능이다.
    @discardableResult
    func applyRecommendation(for slot: RosterSlot) async -> String? {
        guard let sp = rosterSpecies[slot.speciesID],
              let rec = Showdown.set(forSpeciesName: sp.name) else { return nil }
        var applied: [String] = []

        // 기술 — 그 개체가 실제로 배울 수 있는 것만
        let learnable = Set(sp.learnableMoves)
        let moves = rec.movePool.filter { learnable.contains($0) }
        if !moves.isEmpty {
            await setMoves(Array(moves.prefix(4)), for: slot)
            applied.append("기술 \(min(4, moves.count))개")
        }

        // 도구 — 그 종에게 노출되는 것 중에 있으면
        if let want = rec.item {
            let avail = itemsForSpecies[slot.speciesID] ?? []
            if let it = avail.first(where: { $0.name == want }) {
                await setItem(it, for: slot)
                applied.append("도구 \(it.display)")
            }
        }

        // 특성 — 그 종이 가질 수 있는 것 중에 있으면
        let abils = abilitiesForSpecies[slot.speciesID] ?? []
        if let wantAb = rec.abilities.first(where: { w in abils.contains { $0.name == w } }),
           let ab = abils.first(where: { $0.name == wantAb }) {
            await setAbility(ab, for: slot)
            applied.append("특성 \(ab.display)")
        }

        return applied.isEmpty ? nil : applied.joined(separator: ", ")
    }

    /// 팀 전체에 적용
    func applyRecommendationToTeam() async -> Int {
        var count = 0
        for slot in teamSlots where hasRecommendation(for: slot) {
            if await applyRecommendation(for: slot) != nil { count += 1 }
        }
        return count
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
        await preloadAutoForms(for: myTeam)
        if rules.metronomeMode {
            await preloadMetronomePool()
            metronomeTeamSnapshot = await buildMetronomeTeam()
        }

        host.onGuestMessage = { [weak self] msg in
            Task { @MainActor in self?.hostHandle(msg) }
        }
        host.onProtocolError = { [weak self] msg in
            Task { @MainActor in
                self?.errorMessage = msg
                self?.status = "상대를 기다리는 중…"
            }
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
                   hostName: playerName, rules: rules, modeSummary: modeSummary)
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
            var guestTeam = Array(team.prefix(rules.maxTeamSize))
            var hostTeam = Array(myTeam.prefix(rules.maxTeamSize))

            // 토게피 모드는 **양쪽 모두** 고정 팀이다.
            // 게스트는 규칙을 알기 전에 팀을 보내므로 호스트가 여기서 덮어쓴다.
            if rules.metronomeMode {
                let fixed = metronomeTeamSnapshot
                if !fixed.isEmpty {
                    hostTeam = fixed
                    guestTeam = fixed
                }
            }

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
            autoPickLeadIfNeeded()

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
            case .awaitingPivot(let pending) where pending.contains(BattleSide.guest.rawValue):
                if case .replace(let idx) = a { applyPivotHost(.guest, idx) }
            default: break
            }

        case .chat(let from, let text):
            receiveChat(from: from, text: text)

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
        guard let room = discovered.first(where: { !$0.occupied && $0.compatible }) else {
            let incompatible = discovered.filter { !$0.compatible }
            if !incompatible.isEmpty {
                errorMessage = "열린 방(\(incompatible.count)개) 이 모두 버전이 다릅니다.\n"
                    + "양쪽 PokeBattleBar 를 같은 버전으로 맞춰주세요."
            } else {
                errorMessage = "들어갈 수 있는 방이 없습니다. 방을 직접 만들어보세요."
            }
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
        await preloadAutoForms(for: myTeam)

        opponentName = room.hostName
        status = "\(room.hostName) 의 방에 접속 중…"
        screen = .joiningRoom

        // 접속 전에 버전을 먼저 본다 — 붙어봐도 통신이 안 되기 때문
        guard room.compatible else {
            errorMessage = room.protocolVersion > PokeBattleProtocol.version
              ? "\(room.hostName) 님의 PokeBattleBar 가 더 최신입니다 (v\(room.protocolVersion) / 내 v\(PokeBattleProtocol.version)).\n내 앱을 업데이트해주세요."
              : "\(room.hostName) 님의 PokeBattleBar 가 구버전입니다 (v\(room.protocolVersion) / 내 v\(PokeBattleProtocol.version)).\n상대에게 업데이트를 요청해주세요."
            screen = .lobby
            return
        }

        let link = PeerLink(to: room.endpoint)
        link.onProtocolError = { [weak self] msg in
            Task { @MainActor in
                self?.errorMessage = msg
                self?.resetToLobby()
            }
        }
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
            // 토게피 모드는 팀이 고정이므로 호스트 규칙을 받은 뒤 다시 만든다
            if r.metronomeMode {
                Task { @MainActor in
                    self.status = "토게피 모드 준비 중…"
                    await self.preloadMetronomePool()
                    self.myTeam = await self.buildMetronomeTeam()
                    self.autoPickLeadIfNeeded()
                }
            } else if myTeam.count > r.maxTeamSize {
                myTeam = Array(myTeam.prefix(r.maxTeamSize))
            }
            opponentName = hostName
            mySide = BattleSide(rawValue: side) ?? .guest
            chosenLead = nil
            screen = .chooseLead
            status = "선봉을 고르세요"
            autoPickLeadIfNeeded()

        case .joinRejected(let reason):
            errorMessage = reason
            resetToLobby()

        case .battleBegan(let st), .stateChanged(let st):
            battle = st
            if st.steps.isEmpty {
                applyPhaseToUI(st)
            } else {
                playback(st)          // 순서대로 재생한 뒤에 UI 를 연다
            }

        case .chat(let from, let text):
            receiveChat(from: from, text: text)

        case .hostLeft:
            errorMessage = "호스트가 방을 닫았습니다."
            resetToLobby()

        default: break
        }
    }

    // MARK: 선봉 / 행동

    /// 자유의지 모드에서는 선봉도 자동으로 뽑는다.
    func autoPickLeadIfNeeded() {
        guard rules.autoMove || rules.metronomeMode else { return }
        guard chosenLead == nil else { return }
        let count = myState?.team.count ?? sentTeam.count
        guard count > 0 else { return }
        submitLead(Int.random(in: 0..<count))
    }

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
        if rules.autoMove {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                self.advanceAutoIfNeeded()
            }
        }
    }

    /// 이번 턴에 함께 선언할 특수 변신. UI 에서 토글한다.
    var pendingSpecial: SpecialAction?

    func submitMove(_ index: Int) {
        guard !isPlayingBack else { return }
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
        case .mega:
            return rules.allowMega && !me.usedMega && b.canMega
        case .dynamax:
            return rules.allowDynamax && !me.usedDynamax && b.canDynamax
        case .gmax:
            return rules.allowDynamax && rules.allowGigantamax
                && !me.usedDynamax && b.canGigantamax
        case .zMove:
            return rules.allowZMove && !me.usedZMove && b.canZMove
        }
    }

    /// 이미 써버린 변신인지 (UI 에서 "사용함" 표시)
    func alreadyUsed(_ kind: SpecialKind) -> Bool {
        guard let me = myState else { return false }
        switch kind {
        case .mega:            return me.usedMega
        case .dynamax, .gmax:  return me.usedDynamax
        case .zMove:           return me.usedZMove
        }
    }

    func toggleSpecial(_ kind: SpecialKind) {
        guard let b = myState?.active else { return }
        let target: SpecialAction?
        switch kind {
        case .mega:    target = b.megaForms.first.map { SpecialAction.mega(form: $0) }
        case .dynamax: target = .dynamax
        case .gmax:    target = .gmax
        case .zMove:   target = .zMove
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
    /// 메가 폼의 타입·종족값 — 메가진화를 선언했을 때 상성 미리보기에 쓴다
    var megaFormPreview: [String: FormStats] { megaCache }

    func kindOf(_ a: SpecialAction) -> SpecialKind {
        switch a {
        case .mega:    .mega
        case .dynamax: .dynamax
        case .gmax:    .gmax
        case .zMove:   .zMove
        }
    }

    /// 로스터 목록에서 "이 포켓몬은 메가진화/거다이맥스가 된다" 를 표시하기 위한 조회.
    /// 다이맥스는 종족 제한이 없으니 표시하지 않는다 (전부 되기 때문에 정보가 없다).
    func eligibility(for slot: RosterSlot) -> (mega: Bool, gigantamax: Bool, megaFormCount: Int) {
        guard let sp = rosterSpecies[slot.speciesID] else { return (false, false, 0) }
        return (sp.canMega, sp.canGigantamax, sp.megaForms.count)
    }

    func megaFormLabel(_ form: String) -> String {
        megaCache[form]?.suffixLabel ?? (form.hasSuffix("-x") ? "메가 X"
                                        : form.hasSuffix("-y") ? "메가 Y" : "메가")
    }

    private func sameKind(_ a: SpecialAction, _ b: SpecialAction) -> Bool {
        switch (a, b) {
        case (.mega, .mega), (.dynamax, .dynamax), (.gmax, .gmax), (.zMove, .zMove): return true
        default: return false
        }
    }

    func submitReplacement(_ teamIndex: Int) {
        guard let b = battle else { return }
        switch b.phase {
        case .awaitingReplacement:
            if role == .host { applyReplacement(.host, teamIndex) }
            else {
                guestLink?.send(.action(.replace(teamIndex: teamIndex)))
                waitingForOpponent = true
                status = "진행을 기다리는 중…"
            }
        case .awaitingPivot:
            if role == .host { applyPivotHost(.host, teamIndex) }
            else {
                guestLink?.send(.action(.replace(teamIndex: teamIndex)))
                waitingForOpponent = true
                status = "진행을 기다리는 중…"
            }
        default:
            return
        }
    }

    private func applyPivotHost(_ side: BattleSide, _ idx: Int) {
        guard role == .host, var e = engine else { return }
        e.applyPivot(side, teamIndex: idx)
        engine = e
        battle = e.state
        host.send(.stateChanged(state: e.state))
        waitingForOpponent = false
        applyPhaseToUI(e.state)
    }

    /// 유턴으로 물러날 때 내가 골라야 하는가
    var needsMyPivot: Bool {
        guard let b = battle, case .awaitingPivot(let pending) = b.phase else { return false }
        return pending.contains(mySide.rawValue)
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
        if e.state.steps.isEmpty { applyPhaseToUI(e.state) } else { playback(e.state) }
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

    /// 자유의지 모드에서는 호스트가 양쪽 행동을 굴려 스스로 턴을 넘긴다.
    /// 게스트는 화면만 받는다 (양쪽이 따로 굴리면 결과가 갈린다).
    private func advanceAutoIfNeeded() {
        guard role == .host, rules.autoMove, var e = engine else { return }
        switch e.state.phase {
        case .awaitingMoves:
            let h = e.autoAction(for: .host)
            let g = e.autoAction(for: .guest)
            e.resolveTurn(hostAction: h, guestAction: g)
        case .awaitingReplacement(let needs):
            for raw in needs {
                guard let side = BattleSide(rawValue: raw),
                      let pick = e.autoReplacement(for: side) else { continue }
                e.applyReplacement(side, teamIndex: pick)
            }
        case .awaitingPivot(let pending):
            for raw in pending {
                guard let side = BattleSide(rawValue: raw) else { continue }
                let alive = e.state.side(side).aliveIndices
                    .filter { $0 != e.state.side(side).activeIndex }
                guard let pick = alive.randomElement() else { continue }
                e.applyPivot(side, teamIndex: pick)
            }
        default:
            return
        }
        engine = e
        battle = e.state
        host.send(.stateChanged(state: e.state))
        if e.state.steps.isEmpty {
            applyPhaseToUI(e.state)
            if case .finished = e.state.phase { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.advanceAutoIfNeeded()
            }
        } else {
            // 재생이 끝나면 playback 이 다음 턴을 이어서 돌린다
            playback(e.state)
        }
    }

    private func applyPhaseToUI(_ st: BattleState) {
        switch st.phase {
        case .chooseLead:
            screen = .chooseLead
            status = "선봉을 고르세요"
        case .awaitingMoves:
            screen = .battle
            if rules.autoMove {
                waitingForOpponent = true
                status = "자유의지 — 포켓몬이 스스로 싸우는 중…"
            } else {
                waitingForOpponent = false
                status = "기술을 고르세요"
            }
        case .awaitingReplacement(let needs):
            screen = .battle
            if rules.autoMove {
                waitingForOpponent = true
                status = "자유의지 — 다음 포켓몬이 자동으로 나옵니다…"
            } else if needs.contains(mySide.rawValue) {
                waitingForOpponent = false
                status = "다음 포켓몬을 고르세요"
            } else {
                waitingForOpponent = true
                status = "상대가 다음 포켓몬을 고르는 중…"
            }
        case .awaitingPivot(let pending):
            screen = .battle
            if rules.autoMove {
                waitingForOpponent = true
                status = "자유의지 — 물러난 자리에 다음 포켓몬이 나옵니다…"
            } else if pending.contains(mySide.rawValue) {
                waitingForOpponent = false
                status = "물러났습니다 — 다음에 낼 포켓몬을 고르세요"
            } else {
                waitingForOpponent = true
                status = "상대가 교체 중…"
            }
        case .finished:
            screen = .result
            status = ""
            recordResultIfNeeded(st)
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

    // MARK: 채팅

    func sendChat() {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatDraft = ""
        chatLines.append(ChatLine(from: playerName, text: text, mine: true))
        let msg = Wire.chat(from: playerName, text: text)
        if role == .host { host.send(msg) } else { guestLink?.send(msg) }
    }

    private func receiveChat(from: String, text: String) {
        chatLines.append(ChatLine(from: from, text: text, mine: false))
        if chatLines.count > 200 { chatLines.removeFirst(chatLines.count - 200) }
    }

    // MARK: 전적

    private func recordResultIfNeeded(_ st: BattleState) {
        guard case .finished(let winner) = st.phase, lastPointsGained == nil else { return }
        let me = st.sides[mySide.rawValue]
        let draw = winner == nil
        let won = winner == mySide.rawValue
        Task { @MainActor in
            let gained = await RecordStore.shared.finish(
                won: won, draw: draw, opponent: self.opponentName,
                survivors: me.remaining, teamSize: me.team.count)
            self.lastPointsGained = gained
            self.record = await RecordStore.shared.record
        }
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
        playbackTask?.cancel()
        clearPlayback()
        chatLines = []
        chatDraft = ""
        lastPointsGained = nil
        screen = .lobby
    }

    func leaveEverything() {
        if role == .host { host.send(.hostLeft) }
        if role == .guest { guestLink?.send(.leave) }
        resetToLobby()
    }
}
