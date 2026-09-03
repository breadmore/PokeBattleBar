import Foundation

// MARK: - 시드 고정 난수 (호스트가 굴리고, 결과는 로그로 전달되어 재현 가능하다)

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func chance(_ percent: Int) -> Bool {
        guard percent > 0 else { return false }
        guard percent < 100 else { return true }
        return Int.random(in: 1...100, using: &self) <= percent
    }
}

// MARK: - 방 규칙

struct BattleRules: Codable, Hashable, Sendable {
    /// 방장이 정하는 **최대 사용 포켓몬 수**. 각자 보유한 만큼만 데려온다 (비대칭 허용).
    var maxTeamSize: Int = 6
    var level: Int = 50
    /// 상태이상·랭크변화 사용
    var statusEffects: Bool = true
    var statStages: Bool = true
    /// 급소
    var criticalHits: Bool = true
    /// 특수 변신 허용. 각 항목은 **플레이어당 배틀 1회**만 쓸 수 있다.
    var allowMega: Bool = true
    /// 다이맥스 전체 허용 (거다이맥스도 이 토글에 포함된다 — 원작에서 같은 자원이다)
    var allowDynamax: Bool = true
    /// 거다이맥스 폼으로의 발동만 따로 끌 수 있다 (다이맥스는 유지)
    var allowGigantamax: Bool = true
    var allowZMove: Bool = true
    /// 변신에 해당 도구(메가스톤·Z크리스탈·다이맥스밴드) 를 지녀야 하는가.
    /// 끄면 도구 없이도 자격만으로 변신할 수 있다.
    var requireItems: Bool = true
    /// 지닌 도구의 상시 효과(생명의구슬·먹다남은음식 등) 사용
    var itemEffects: Bool = true
    /// 특성 사용
    var abilities: Bool = true
    /// 날씨 · 필드 사용
    var weather: Bool = true
    /// 교체 허용. 기본은 꺼짐 (쓰러져야 다음 포켓몬이 나온다).
    /// 켜면 조임·스텔스록 같은 효과가 교체에도 그대로 작동한다.
    var allowSwitching: Bool = false

    static let `default` = BattleRules()
}

// MARK: - 배틀 상태

enum BattleSide: Int, Codable, Sendable {
    case host = 0, guest = 1
    var other: BattleSide { self == .host ? .guest : .host }
}

struct SideState: Codable, Sendable, Equatable {
    var playerName: String
    var team: [Battler]
    var activeIndex: Int
    /// **배틀 전체에서 한 번씩만.** 6마리가 다 거다이맥스할 수는 없다.
    var usedMega: Bool = false
    /// 다이맥스와 거다이맥스가 함께 쓰는 슬롯 (원작에서 같은 자원)
    var usedDynamax: Bool = false
    var usedZMove: Bool = false
    /// 이 진영에 설치된 장애물. 등장하는 포켓몬이 피해를 받는다.
    var hazards: Set<Hazard> = []

    func hasUsed(_ a: SpecialAction) -> Bool {
        switch a {
        case .mega:            usedMega
        case .dynamax, .gmax:  usedDynamax
        case .zMove:           usedZMove
        }
    }
    var active: Battler { team[activeIndex] }
    var remaining: Int { team.filter { !$0.isFainted }.count }
    var aliveIndices: [Int] {
        team.indices.filter { !team[$0].isFainted }
    }
}

enum BattlePhase: Codable, Sendable, Equatable {
    case chooseLead                       // 선봉 선택
    case awaitingMoves                    // 양쪽 기술 선택 대기
    case awaitingReplacement([Int])       // 교체가 필요한 side raw 값들
    case finished(winner: Int?)           // nil = 무승부
}

struct BattleState: Codable, Sendable, Equatable {
    var rules: BattleRules
    var sides: [SideState]                // index == BattleSide.rawValue
    var turn: Int = 0
    var phase: BattlePhase = .chooseLead
    var log: [String] = []
    /// 날씨 / 필드
    var field = FieldState()
    /// G-Max 지속 피해 (side.rawValue -> (면역타입, 남은턴))
    var gmaxDoT: [Int: GMaxDoT] = [:]

    func side(_ s: BattleSide) -> SideState { sides[s.rawValue] }
}

// MARK: - 행동

/// G-Max 지속 피해 상태
struct GMaxDoT: Codable, Sendable, Equatable {
    var immuneType: PType
    var turnsLeft: Int
}

enum BattleAction: Codable, Sendable, Equatable {
    /// 기술을 쓴다. `special` 은 이번 턴에 함께 선언하는 특수 변신
    /// (원작처럼 기술 선택과 같은 시점에 선언한다).
    case useMove(index: Int, special: SpecialAction? = nil)
    case replace(teamIndex: Int)
    /// 자발적 교체 (rules.allowSwitching 이 켜진 경우에만).
    /// 조임 상태면 막히고, 교체로 나온 포켓몬은 장애물 피해를 받는다.
    case switchTo(teamIndex: Int)

    var moveIndex: Int? {
        if case .useMove(let i, _) = self { return i }
        return nil
    }
    var switchIndex: Int? {
        if case .switchTo(let i) = self { return i }
        return nil
    }
    var isSwitch: Bool { switchIndex != nil }
    var special: SpecialAction? {
        if case .useMove(_, let s) = self { return s }
        return nil
    }
}

// MARK: - 엔진 (호스트에서만 실행)

struct BattleEngine {
    var state: BattleState
    let chart: TypeChart
    private var rng: SeededRNG

    /// 메가 / 거다이맥스 폼의 종족값. 배틀 시작 전에 호스트가 채워 넣는다
    /// (배틀 중에 네트워크를 기다리면 안 되므로 미리 받아둔다).
    var megaCache: [String: FormStats] = [:]
    var gmaxCache: [String: FormStats] = [:]
    /// Z기술 정의 (타입+분류별). 마찬가지로 미리 받아둔다.
    var zMoveCache: [String: MoveDef] = [:]
    /// 맥스 기술 정의 (거다이맥스 중 기술이 이걸로 바뀐다).
    var maxMoveCache: [String: MoveDef] = [:]

    init(state: BattleState, chart: TypeChart, seed: UInt64) {
        self.state = state
        self.chart = chart
        self.rng = SeededRNG(seed: seed)
    }

    private mutating func say(_ s: String) { state.log.append(s) }

    // MARK: 선봉 확정

    /// 선봉을 정한다. 범위를 벗어난 인덱스를 **조용히 무시하면** activeIndex 가 0 에 남아
    /// "고른 포켓몬이 아니라 맨 왼쪽이 나온다"가 된다. 그래서 클램프하고 흔적을 남긴다.
    mutating func setLead(_ side: BattleSide, index: Int) {
        let team = state.sides[side.rawValue].team
        guard !team.isEmpty else { return }
        if team.indices.contains(index) {
            state.sides[side.rawValue].activeIndex = index
            return
        }
        let clamped = max(0, min(index, team.count - 1))
        state.sides[side.rawValue].activeIndex = clamped
        say("[경고] 선봉 인덱스 \(index) 가 팀 범위(0..<\(team.count))를 벗어나 \(clamped) 로 보정됐습니다.")
    }

    mutating func beginBattle() {
        state.phase = .awaitingMoves
        state.turn = 1
        for s in [BattleSide.host, .guest] {
            let a = state.side(s).active
            say("\(state.side(s).playerName): 가라, \(a.name)!")
        }
        for s in [BattleSide.host, .guest] { fireEntryAbility(s) }
    }

    /// 자발적 교체. 조임 상태면 실패한다.
    private mutating func performSwitch(_ side: BattleSide, teamIndex: Int) {
        guard state.rules.allowSwitching else { return }
        let team = state.side(side).team
        let cur = state.side(side).activeIndex
        guard team.indices.contains(teamIndex), teamIndex != cur,
              !team[teamIndex].isFainted else { return }

        let active = team[cur]
        if active.isTrapped {
            say("\(active.name)는 묶여 있어 교체할 수 없다!")
            return
        }

        // 물러나는 포켓몬의 일시 상태를 초기화한다 (원작과 동일)
        var out = active
        out.stages = [:]
        out.accuracyStage = 0
        out.evasionStage = 0
        out.confusionTurns = 0
        out.mustFlinch = false
        out.lockedMoveIndex = nil
        out.lastMoveIndex = nil
        out.tormented = false
        out.isProtecting = false
        out.protectStreak = 0
        if out.isDynamaxed { out.revertDynamax() }
        state.sides[side.rawValue].team[cur] = out

        state.sides[side.rawValue].activeIndex = teamIndex
        say("\(state.side(side).playerName)는 \(out.name)을(를) 넣고 \(team[teamIndex].name)을(를) 냈다!")

        applyHazards(to: side)
        if state.side(side).active.isFainted {
            checkBattleOver()
            if case .finished = state.phase { return }
            state.phase = .awaitingReplacement([side.rawValue])
            return
        }
        fireEntryAbility(side)
    }

    /// 등장 시 장애물 피해. 교체룰이 들어오면 교체에도 그대로 적용된다.
    private mutating func applyHazards(to side: BattleSide) {
        let hazards = state.side(side).hazards
        guard !hazards.isEmpty else { return }
        let idx = state.side(side).activeIndex
        guard state.side(side).team.indices.contains(idx) else { return }
        var b = state.sides[side.rawValue].team[idx]
        guard !b.isFainted else { return }
        if state.rules.abilities, isMagicGuard(b) { return }

        for h in Hazard.allCases where hazards.contains(h) {
            let mult = chart.multiplier(attack: h.type, defenders: b.types)
            guard mult > 0 else { continue }
            let dmg = h.damage(maxHP: b.maxHP, multiplier: mult)
            b.currentHP = max(0, b.currentHP - dmg)
            say("\(KO.t(b.name)) \(h.ko)에 피해를 입었다!")
            if b.currentHP == 0 { break }
        }
        state.sides[side.rawValue].team[idx] = b
        if b.isFainted {
            let marker = "\(KO.t(b.name)) 쓰러졌다!"
            if state.log.last != marker { say(marker) }
        }
    }

    /// 등장 시 발동하는 특성 (위협)
    private mutating func fireEntryAbility(_ side: BattleSide) {
        guard state.rules.abilities else { return }
        let idx = state.side(side).activeIndex
        guard state.side(side).team.indices.contains(idx) else { return }
        var b = state.sides[side.rawValue].team[idx]
        guard !b.entryAbilityFired, !b.isFainted else { return }
        b.entryAbilityFired = true
        state.sides[side.rawValue].team[idx] = b

        // 날씨를 부르는 특성 (가뭄·잔비·모래날림·눈퍼뜨리기)
        if state.rules.weather, case .weatherOnEntry(let w) = b.abilityKind {
            state.field.setWeather(w, turns: 5)
            say("\(b.name)의 \(b.ability?.display ?? "특성")! \(w.ko) 상태가 되었다!")
        }

        guard case .intimidate = b.abilityKind else { return }
        let foe = side.other
        let fIdx = state.side(foe).activeIndex
        guard state.side(foe).team.indices.contains(fIdx) else { return }
        var f = state.sides[foe.rawValue].team[fIdx]
        guard !f.isFainted else { return }
        if case .clearBody = f.abilityKind {
            say("\(f.name)는 \(f.ability?.display ?? "특성") 때문에 능력치가 떨어지지 않는다!")
            return
        }
        let cur = f.stages[.attack] ?? 0
        guard cur > -6 else { return }
        f.stages[.attack] = cur - 1
        state.sides[foe.rawValue].team[fIdx] = f
        say("\(b.name)의 위협! \(f.name)의 공격이 떨어졌다!")
    }

    // MARK: 한 턴 처리

    /// 양쪽 행동을 받아 한 턴을 끝까지 해석한다.
    /// 이번 턴 각 진영이 선언한 Z기술 (기술 자체를 바꿔 쓰므로 따로 들고 있는다)
    private var zDeclared: Set<Int> = []

    mutating func resolveTurn(hostAction: BattleAction, guestAction: BattleAction) {
        guard case .awaitingMoves = state.phase else { return }

        // 이번 턴 방어 상태를 초기화한다 (방어는 그 턴에만 유효하다)
        for side in [BattleSide.host, .guest] {
            let i = state.side(side).activeIndex
            if state.side(side).team.indices.contains(i) {
                state.sides[side.rawValue].team[i].isProtecting = false
            }
        }

        // 교체는 기술보다 먼저 처리한다 (원작 규칙).
        // 스피드가 빠른 쪽부터 교체한다.
        if state.rules.allowSwitching {
            let switchOrder = state.side(.host).active.effective(.speed)
                            >= state.side(.guest).active.effective(.speed)
                            ? [BattleSide.host, .guest] : [.guest, .host]
            for side in switchOrder {
                let action = side == .host ? hostAction : guestAction
                if let idx = action.switchIndex { performSwitch(side, teamIndex: idx) }
            }
            if case .finished = state.phase { return }
        }

        // 변신은 공격보다 먼저 일어난다 — 바뀐 스피드가 행동 순서에 반영되어야 한다.
        zDeclared = []
        applySpecial(hostAction.special, for: .host)
        applySpecial(guestAction.special, for: .guest)

        let order = turnOrder(hostAction: hostAction, guestAction: guestAction)

        for side in order {
            if case .finished = state.phase { break }
            // 이미 쓰러진 포켓몬은 행동하지 않는다
            if state.side(side).active.isFainted { continue }
            let action = side == .host ? hostAction : guestAction
            if let idx = action.moveIndex {
                performMove(attacker: side, moveIndex: idx)
            }
        }

        if case .finished = state.phase { return }

        endOfTurn()

        if case .finished = state.phase { return }

        // 쓰러진 쪽은 다음 포켓몬을 골라야 한다 (교체 없음 — 쓰러져야 등장)
        var needs: [Int] = []
        for s in [BattleSide.host, .guest] where state.side(s).active.isFainted {
            needs.append(s.rawValue)
        }
        if needs.isEmpty {
            state.turn += 1
            state.phase = .awaitingMoves
        } else {
            state.phase = .awaitingReplacement(needs)
        }
    }

    /// 쓰러진 자리에 다음 포켓몬을 낸다.
    mutating func applyReplacement(_ side: BattleSide, teamIndex: Int) {
        guard case .awaitingReplacement(var needs) = state.phase else { return }
        guard needs.contains(side.rawValue) else { return }
        let team = state.side(side).team
        guard team.indices.contains(teamIndex) else {
            say("[경고] 교체 인덱스 \(teamIndex) 가 팀 범위(0..<\(team.count))를 벗어났습니다.")
            return
        }
        guard !team[teamIndex].isFainted else { return }

        state.sides[side.rawValue].activeIndex = teamIndex
        say("\(state.side(side).playerName): 가라, \(team[teamIndex].name)!")
        applyHazards(to: side)
        guard !state.side(side).active.isFainted else {
            // 장애물로 쓰러졌으면 또 골라야 한다
            checkBattleOver()
            if case .finished = state.phase { return }
            state.phase = .awaitingReplacement([side.rawValue])
            return
        }
        fireEntryAbility(side)

        needs.removeAll { $0 == side.rawValue }
        if needs.isEmpty {
            state.turn += 1
            state.phase = .awaitingMoves
        } else {
            state.phase = .awaitingReplacement(needs)
        }
    }

    // MARK: 행동 순서

    private mutating func turnOrder(hostAction: BattleAction, guestAction: BattleAction) -> [BattleSide] {
        func priority(_ a: BattleAction, _ s: BattleSide) -> Int {
            if let i = a.moveIndex {
                let mv = state.side(s).active.moves
                if mv.indices.contains(i) {
                    // 방어 계열은 우선도 +4 (원작)
                    if MoveFlags.isProtect(mv[i].def.name) { return 4 }
                    return mv[i].def.priority
                }
            }
            return 0
        }
        var hp = priority(hostAction, .host), gp = priority(guestAction, .guest)

        // 선제공격손톱 — 확률로 우선도를 한 칸 올린다 (원작 3/16)
        if state.rules.itemEffects {
            if case .quickClaw(let n, let d) = state.side(.host).active.itemKind,
               Int.random(in: 1...d, using: &rng) <= n {
                say("\(state.side(.host).active.name)의 선제공격손톱이 발동했다!")
                hp += 1
            }
            if case .quickClaw(let n, let d) = state.side(.guest).active.itemKind,
               Int.random(in: 1...d, using: &rng) <= n {
                say("\(state.side(.guest).active.name)의 선제공격손톱이 발동했다!")
                gp += 1
            }
        }
        if hp != gp { return hp > gp ? [.host, .guest] : [.guest, .host] }

        func speed(_ side: BattleSide) -> Int {
            let b = state.side(side).active
            var v = Double(b.effective(.speed))
            if state.rules.itemEffects, case .choice(.speed) = b.itemKind { v *= 1.5 }
            // 엽록소·쓱쓱·모래헤치기·눈치우기
            if state.rules.weather, state.field.hasWeather,
               case .weatherSpeedBoost(let w, let m) = b.abilityKind,
               w == state.field.weather { v *= m }
            return max(1, Int(v))
        }
        let hs = speed(.host)
        let gs = speed(.guest)
        if hs != gs { return hs > gs ? [.host, .guest] : [.guest, .host] }
        return Bool.random(using: &rng) ? [.host, .guest] : [.guest, .host]
    }

    // MARK: 특수 변신 (메가 / 거다이맥스 / Z기술)

    /// 선언된 변신을 적용한다. **플레이어당 각 종류 1회**, 자격 있는 개체만.
    private mutating func applySpecial(_ action: SpecialAction?, for side: BattleSide) {
        guard let action else { return }
        var s = state.sides[side.rawValue]
        let idx = s.activeIndex
        guard s.team.indices.contains(idx) else { return }

        // 규칙에서 껐거나, 이미 이 배틀에서 썼으면 무시한다
        switch action {
        case .mega    where !state.rules.allowMega:                                   return
        case .dynamax where !state.rules.allowDynamax:                                return
        case .gmax    where !(state.rules.allowDynamax && state.rules.allowGigantamax): return
        case .zMove   where !state.rules.allowZMove:                                  return
        default: break
        }
        guard !s.hasUsed(action) else {
            // 다이맥스와 거다이맥스는 같은 슬롯이므로 안내 문구도 그렇게 나가야 한다
            let what = action.sharesDynamaxSlot ? "다이맥스" : action.ko
            say("[안내] \(s.playerName)는 이번 배틀에서 \(what)을 이미 사용했습니다.")
            return
        }

        var b = s.team[idx]

        switch action {
        case .mega(let form):
            guard b.canMega(requiringItem: state.rules.requireItems),
                  b.megaForms.contains(form), let stats = megaCache[form] else {
                if state.rules.requireItems, b.canMega, b.megaFormFromItem == nil {
                    say("[안내] \(b.name)는 메가스톤을 지니고 있지 않습니다.")
                }
                return
            }
            // 도구가 특정 폼을 지정하면 그것을 우선한다
            if state.rules.requireItems, let itemForm = b.megaFormFromItem, itemForm != form {
                guard let alt = megaCache[itemForm] else { return }
                b.applyMega(form: alt, nature: Nature.named(natureOf(b)))
                s.usedMega = true
                s.team[idx] = b
                state.sides[side.rawValue] = s
                say("\(s.playerName)의 \(b.name)이(가) \(b.formLabel ?? "메가")로 진화했다!")
                return
            }
            _ = stats
            b.applyMega(form: stats, nature: Nature.named(natureOf(b)))
            s.usedMega = true
            say("\(s.playerName)의 \(b.name)이(가) \(b.formLabel ?? "메가")로 진화했다!")

        case .dynamax:
            guard b.canDynamax(requiringItem: state.rules.requireItems) else {
                if state.rules.requireItems { say("[안내] \(b.name)는 다이맥스 밴드를 지니고 있지 않습니다.") }
                return
            }
            b.applyDynamax(form: nil, gigantamax: false,
                           turns: FormTables.dynamaxTurns,
                           multiplier: FormTables.dynamaxHPMultiplier)
            s.usedDynamax = true
            say("\(s.playerName)의 \(b.name)이(가) 다이맥스했다! (\(FormTables.dynamaxTurns)턴)")

        case .gmax:
            guard b.canGigantamax(requiringItem: state.rules.requireItems) else {
                if state.rules.requireItems, b.canGigantamax {
                    say("[안내] \(b.name)는 다이버섯(또는 다이맥스 밴드) 을 지니고 있지 않습니다.")
                }
                return
            }
            b.applyDynamax(form: b.gmaxForm.flatMap { gmaxCache[$0] }, gigantamax: true,
                           turns: FormTables.dynamaxTurns,
                           multiplier: FormTables.dynamaxHPMultiplier)
            s.usedDynamax = true
            say("\(s.playerName)의 \(b.name)이(가) 거다이맥스했다! (\(FormTables.dynamaxTurns)턴)")

        case .zMove:
            guard b.canZMove(requiringItem: state.rules.requireItems) else {
                if state.rules.requireItems { say("[안내] \(b.name)는 맞는 Z크리스탈을 지니고 있지 않습니다.") }
                return
            }
            s.usedZMove = true
            zDeclared.insert(side.rawValue)
            say("\(s.playerName)의 \(b.name)이(가) Z파워를 해방했다!")
        }

        s.team[idx] = b
        state.sides[side.rawValue] = s
    }

    /// 성격은 Battler 에 한글명으로만 남아 있어서 역매핑한다 (메가 스탯 재계산에 필요).
    private func natureOf(_ b: Battler) -> String {
        Nature.koNames.first { $0.value == b.natureName }?.key ?? "serious"
    }

    /// 다이맥스/거다이맥스 지속시간을 줄이고, 끝나면 되돌린다.
    private mutating func tickDynamax() {
        for side in [BattleSide.host, .guest] {
            let idx = state.side(side).activeIndex
            guard state.side(side).team.indices.contains(idx) else { continue }
            var b = state.sides[side.rawValue].team[idx]
            guard b.isDynamaxed else { continue }
            let wasGiga = b.isGigantamaxed
            b.dynamaxTurnsLeft -= 1
            if b.dynamaxTurnsLeft <= 0 {
                b.revertDynamax()
                say("\(b.name)의 \(wasGiga ? "거다이맥스" : "다이맥스")가 끝났다!")
            }
            state.sides[side.rawValue].team[idx] = b
        }
    }

    // MARK: 기술 사용

    private mutating func performMove(attacker: BattleSide, moveIndex: Int) {
        let defender = attacker.other
        var atk = state.side(attacker).active
        let atkName = atk.name

        guard atk.moves.indices.contains(moveIndex) else { return }
        guard atk.moves[moveIndex].usable else {
            say("\(atkName)의 \(atk.moves[moveIndex].def.display)! …PP가 없다!")
            return
        }

        // 아무것도않기 — 같은 기술을 연속으로 쓸 수 없다
        if atk.tormented, atk.lastMoveIndex == moveIndex {
            say("\(atkName)는 같은 기술을 연속으로 쓸 수 없다!")
            return
        }

        // 구애 계열로 고정된 기술이 아니면 쓸 수 없다
        if state.rules.itemEffects, let locked = atk.lockedMoveIndex, locked != moveIndex,
           atk.moves.indices.contains(locked), atk.moves[locked].usable {
            say("\(atkName)는 \(atk.heldItem?.display ?? "구애 도구") 때문에 \(atk.moves[locked].def.display)밖에 쓸 수 없다!")
            return
        }
        // 돌격조끼: 변화기를 쓸 수 없다
        if state.rules.itemEffects, case .assaultVest = atk.itemKind,
           atk.moves[moveIndex].def.damageClass == .status {
            say("\(atkName)는 돌격조끼 때문에 변화기를 쓸 수 없다!")
            return
        }

        // 행동 방해 판정
        if let blocked = checkPreMoveBlock(&atk, side: attacker) {
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = atk
            say(blocked)
            return
        }

        atk.moves[moveIndex].ppLeft -= 1
        let baseMove = atk.moves[moveIndex].def
        state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = atk

        // Z기술 / 맥스기술 변환. 위력은 PokeAPI 가 주지 않으므로 원작 변환표를 쓴다.
        let move = transformed(baseMove, attacker: attacker)
        if move.name != baseMove.name {
            say("\(atkName)의 \(baseMove.display) → \(move.display)!")
        } else {
            say("\(atkName)의 \(move.display)!")
        }

        // 직전 기술 기록 (아무것도않기 판정용)
        do {
            var a2 = state.side(attacker).active
            a2.lastMoveIndex = moveIndex
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a2
        }

        // 방어 계열 — 이번 턴 자신을 보호한다. 연속으로 쓰면 성공률이 떨어진다.
        if MoveFlags.isProtect(move.name) {
            var a2 = state.side(attacker).active
            let successPercent = max(13, 100 >> a2.protectStreak)
            if rng.chance(successPercent) {
                a2.isProtecting = true
                a2.protectStreak = min(3, a2.protectStreak + 1)
                state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a2
                say("\(atkName)는 몸을 지킬 준비를 했다!")
            } else {
                a2.protectStreak = 0
                state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a2
                say("\(atkName)의 \(move.display)! …하지만 실패했다!")
            }
            return
        }
        // 방어 기술이 아니면 연속 카운터를 초기화한다
        if state.side(attacker).active.protectStreak > 0 {
            var a2 = state.side(attacker).active
            a2.protectStreak = 0
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a2
        }

        // 상대가 방어 중이면 막힌다 — 다이맥스일격/연격만 관통한다
        let bypassesProtect: Bool = {
            guard move.name.hasPrefix("gmax-"),
                  let g = state.side(attacker).active.gmaxMove else { return false }
            if case .bypassProtect = g.effect { return true }
            return false
        }()
        if state.side(defender).active.isProtecting, !bypassesProtect {
            say("\(state.side(defender).active.name)는 공격을 막아냈다!")
            return
        }

        // 방음 — 소리 기술 무효
        if state.rules.abilities, MoveFlags.isSound(move.name),
           case .soundImmunity = state.side(defender).active.abilityKind {
            say("\(state.side(defender).active.name)는 방음으로 소리 기술을 막았다!")
            return
        }
        // 가루 기술은 풀타입에게 통하지 않는다 (원작 규칙)
        if MoveFlags.isPowder(move.name), state.side(defender).active.types.contains(.grass) {
            say("\(state.side(defender).active.name)에게는 가루 기술이 통하지 않는다!")
            return
        }

        // 명중 판정
        let def = state.side(defender).active
        if !accuracyCheck(move: move, attacker: atk, defender: def) {
            say("\(atkName)의 공격은 빗나갔다!")
            // 대폭발 계열은 빗나가도 쓴 쪽이 쓰러진다 (5세대 이후 원작 규칙 —
            // 자폭이 공격 판정보다 먼저 일어나기 때문이다)
            if move.selfKO { applySelfKO(attacker) }
            return
        }

        // 변화기 (고정 데미지 기술은 위력이 0 이어도 공격기다)
        if move.damageClass == .status || !move.isDamaging {
            // **타입 면역은 변화기에도 적용된다** (원작 규칙).
            // 전기자석파는 땅 타입에게, 최면술은 악 타입에게 통하지 않는다.
            // 날씨·필드 기술은 상대를 노리지 않으므로 대상에서 제외한다.
            if move.targetsOpponent {
                let d = state.side(defender).active
                var mult = chart.multiplier(attack: move.type, defenders: d.types)
                // 부유 등 특성 면역도 함께 본다
                if state.rules.abilities, case .typeImmunity(let t) = d.abilityKind, move.type == t {
                    mult = 0
                }
                if mult == 0 {
                    say("\(d.name)에게는 효과가 없는 것 같다…")
                    if move.selfKO { applySelfKO(attacker) }
                    return
                }
            }
            applyNonDamaging(move: move, attacker: attacker, defender: defender)
            // 메멘토·힐링위시처럼 위력 없이 쓴 쪽이 쓰러지는 기술
            if move.selfKO { applySelfKO(attacker) }
            return
        }

        // 공격기 — 다단히트 지원
        let hits = hitCount(move)
        var totalDealt = 0
        var lastMult = 1.0
        var didCrit = false

        for _ in 0..<hits {
            if state.side(defender).active.isFainted { break }
            let r = computeDamage(move: move, attacker: attacker, defender: defender)
            lastMult = r.typeMultiplier
            if r.multiplier == 0 {
                say("\(state.side(defender).active.name)에게는 효과가 없는 것 같다…")
                // 상대가 무효 타입이어도 자폭은 일어난다
                if move.selfKO { applySelfKO(attacker) }
                return
            }
            didCrit = didCrit || r.critical
            totalDealt += applyDamage(r.damage, to: defender)
        }

        if hits > 1 { say("\(hits)번 맞았다!") }
        if didCrit { say("급소에 맞았다!") }
        if let t = TypeChart.effectivenessText(lastMult) { say(t) }

        // 흡수 / 반동
        if move.drainPercent != 0, totalDealt > 0 {
            var a = state.side(attacker).active
            let delta = totalDealt * move.drainPercent / 100
            if delta > 0 {
                a.currentHP = min(a.maxHP, a.currentHP + delta)
                say("\(KO.t(a.name)) 체력을 회복했다!")
            } else if delta < 0 {
                if state.rules.abilities,
                   { if case .rockHead = a.abilityKind { return true }; return false }() {
                    say("\(KO.t(a.name)) 돌머리 덕분에 반동을 받지 않았다!")
                } else {
                    a.currentHP = max(0, a.currentHP + delta)
                    say("\(KO.t(a.name)) 반동 데미지를 받았다!")
                }
            }
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a
            checkFaint(attacker)
        }

        // 부가효과 (데미지를 준 뒤에만)
        if !state.side(defender).active.isFainted {
            applySecondary(move: move, attacker: attacker, defender: defender)
        }

        checkFaint(defender)

        // 생명의구슬 반동 — 데미지를 준 경우에만
        if state.rules.itemEffects, totalDealt > 0, case .lifeOrb = atk.itemKind,
           !(state.rules.abilities && isMagicGuard(state.side(attacker).active)) {
            var a2 = state.side(attacker).active
            let recoil = max(1, a2.maxHP / 10)
            a2.currentHP = max(0, a2.currentHP - recoil)
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a2
            say("\(a2.name)는 생명의구슬의 반동을 받았다!")
            checkFaint(attacker)
        }

        // 접촉 기술에 대한 반격 특성 (정전기·불꽃몸·거친피부 등)
        if state.rules.abilities, totalDealt > 0, MoveFlags.isContact(move.name) {
            applyContactAbility(attacker: attacker, defender: defender)
        }

        // 거다이맥스 전용기 추가 효과
        if move.name.hasPrefix("gmax-"),
           let g = state.side(attacker).active.gmaxMove {
            applyGMaxEffect(g, attacker: attacker, defender: defender)
        }

        // 구애 계열 — 처음 쓴 기술로 고정된다
        lockChoiceMove(attacker, moveIndex: moveIndex)

        // 대폭발·자폭·목숨걸기 — 쓴 쪽이 쓰러진다.
        // PokeAPI 의 meta 에는 이 정보가 없어서 예전엔 그냥 무시됐다.
        if move.selfKO { applySelfKO(attacker) }
    }

    /// 이번 턴에 실제로 쓰이는 기술. Z기술 선언이나 거다이맥스 상태면 다른 기술로 바뀐다.
    private func transformed(_ move: MoveDef, attacker: BattleSide) -> MoveDef {
        let b = state.side(attacker).active

        // 다이맥스/거다이맥스 중에는 모든 기술이 맥스 기술이 된다 (원작과 동일)
        if b.isDynamaxed {
            if move.damageClass == .status {
                if var guardMove = maxMoveCache[FormTables.maxGuard] {
                    guardMove.pp = move.pp
                    return guardMove
                }
                return move
            }
            // 거다이맥스 전용기 — 기술 타입이 전용기 타입과 같을 때 발동한다 (원작과 동일)
            if let g = b.gmaxMove, g.type == move.type {
                var gm = move
                gm.name = "gmax-" + g.rawValue
                gm.koName = g.ko
                gm.power = FormTables.maxPower(basePower: move.power ?? 0, type: move.type)
                gm.accuracy = nil
                gm.specialDamage = .none
                gm.selfKO = false
                gm.ailment = .none
                gm.statChanges = []
                return gm
            }
            guard let name = FormTables.maxMove[move.type],
                  var mx = maxMoveCache[name] else { return move }
            mx.power = FormTables.maxPower(basePower: move.power ?? 0, type: move.type)
            mx.damageClass = move.damageClass      // 물리/특수는 원래 기술을 따른다
            mx.accuracy = nil                      // 맥스 기술은 빗나가지 않는다
            mx.specialDamage = .none
            mx.selfKO = false                      // 다이맥스 중 대폭발은 자폭하지 않는다
            return mx
        }

        // Z기술 — 이번 턴 한 번만
        guard zDeclared.contains(attacker.rawValue) else { return move }
        // 전용 Z크리스탈은 타입 제한 없이 자기 공격기를 Z기술로 만든다
        if b.hasSignatureZ, move.damageClass != .status, move.isDamaging {
            var sz = move
            sz.koName = (b.heldItem?.display ?? "전용 Z") + " Z기술"
            sz.power = FormTables.zPower(basePower: move.power ?? 0)
            sz.accuracy = nil
            sz.specialDamage = .none
            sz.selfKO = false
            return sz
        }
        guard let zName = FormTables.zMoveName(for: move),
              var z = zMoveCache[zName] else { return move }
        z.power = FormTables.zPower(basePower: move.power ?? 0)
        z.damageClass = move.damageClass
        z.accuracy = nil                           // Z기술은 필중
        z.specialDamage = .none
        z.selfKO = false
        return z
    }

    /// 접촉했을 때 방어측 특성이 공격측에게 되돌리는 효과
    private mutating func applyContactAbility(attacker: BattleSide, defender: BattleSide) {
        let d = state.side(defender).active
        guard !d.isFainted else { return }

        switch d.abilityKind {
        case .contactStatus(let ail, let percent):
            guard rng.chance(percent) else { return }
            inflictDirect(ail, on: attacker, source: d.ability?.display ?? "특성")

        case .contactDamage(let denom):
            var a = state.sides[attacker.rawValue].team[state.side(attacker).activeIndex]
            guard !a.isFainted, !(state.rules.abilities && isMagicGuard(a)) else { return }
            a.currentHP = max(0, a.currentHP - max(1, a.maxHP / denom))
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a
            say("\(KO.t(a.name)) \(d.ability?.display ?? "특성") 때문에 피해를 입었다!")
            checkFaint(attacker)

        default:
            break
        }
    }

    /// 거다이맥스 전용기의 추가 효과를 적용한다.
    /// 교체가 없는 배틀이라 스텔스록·묶기·중력 계열은 재현 대상이 아니다.
    private mutating func applyGMaxEffect(_ g: GMaxMove, attacker: BattleSide, defender: BattleSide) {
        let aIdx = state.side(attacker).activeIndex
        let dIdx = state.side(defender).activeIndex
        guard state.side(attacker).team.indices.contains(aIdx),
              state.side(defender).team.indices.contains(dIdx) else { return }

        switch g.effect {
        case .none:
            break

        case .damageOverTime(let immune, let turns):
            state.gmaxDoT[defender.rawValue] = GMaxDoT(immuneType: immune, turnsLeft: turns)
            say("\(g.ko)의 여파가 상대를 감쌌다! (\(turns)턴)")

        case .inflict(let ail):
            inflictDirect(ail, on: defender, source: g.ko)

        case .inflictRandom(let list):
            if let pick = list.randomElement(using: &rng) {
                inflictDirect(pick, on: defender, source: g.ko)
            }

        case .foeStat(let stat, let delta):
            var f = state.sides[defender.rawValue].team[dIdx]
            guard !f.isFainted else { break }
            if state.rules.abilities, case .clearBody = f.abilityKind {
                say("\(f.name)는 \(f.ability?.display ?? "특성") 때문에 능력치가 떨어지지 않는다!")
                break
            }
            let cur = f.stages[stat] ?? 0
            f.stages[stat] = max(-6, min(6, cur + delta))
            state.sides[defender.rawValue].team[dIdx] = f
            say("\(f.name)의 \(KO.s(stat.ko)) \(delta > 0 ? "올라갔다" : "크게 떨어졌다")!")

        case .foeEvasion(let delta):
            var f = state.sides[defender.rawValue].team[dIdx]
            guard !f.isFainted else { break }
            f.evasionStage = max(-6, min(6, f.evasionStage + delta))
            state.sides[defender.rawValue].team[dIdx] = f
            say("\(f.name)의 회피율이 떨어졌다!")

        case .selfStat(let stat, let delta):
            var a = state.sides[attacker.rawValue].team[aIdx]
            let cur = a.stages[stat] ?? 0
            a.stages[stat] = max(-6, min(6, cur + delta))
            state.sides[attacker.rawValue].team[aIdx] = a
            say("\(a.name)의 \(KO.s(stat.ko)) 올라갔다!")

        case .selfCrit(let n):
            var a = state.sides[attacker.rawValue].team[aIdx]
            a.critStage = min(4, a.critStage + n)
            state.sides[attacker.rawValue].team[aIdx] = a
            say("\(a.name)의 급소율이 올라갔다!")

        case .healSelf(let percent):
            var a = state.sides[attacker.rawValue].team[aIdx]
            guard a.currentHP < a.maxHP else { break }
            a.currentHP = min(a.maxHP, a.currentHP + max(1, a.maxHP * percent / 100))
            state.sides[attacker.rawValue].team[aIdx] = a
            say("\(KO.t(a.name)) 체력을 회복했다!")

        case .cureStatus:
            var a = state.sides[attacker.rawValue].team[aIdx]
            guard a.status != .none || a.confusionTurns > 0 else { break }
            a.status = .none; a.sleepTurns = 0; a.toxicCounter = 0; a.confusionTurns = 0
            state.sides[attacker.rawValue].team[aIdx] = a
            say("\(KO.t(a.name)) 상태이상이 회복됐다!")

        case .drainPP(let n):
            var f = state.sides[defender.rawValue].team[dIdx]
            guard !f.isFainted, !f.moves.isEmpty else { break }
            let i = Int.random(in: 0..<f.moves.count, using: &rng)
            f.moves[i].ppLeft = max(0, f.moves[i].ppLeft - n)
            state.sides[defender.rawValue].team[dIdx] = f
            say("\(f.name)의 \(f.moves[i].def.display) PP가 줄었다!")

        case .ignoreAbility:
            var f = state.sides[defender.rawValue].team[dIdx]
            guard f.ability != nil else { break }
            f.ability = nil
            state.sides[defender.rawValue].team[dIdx] = f
            say("상대의 특성이 무시됐다!")

        case .damageOverTimeAndTrap(let immune, let turns):
            state.gmaxDoT[defender.rawValue] = GMaxDoT(immuneType: immune, turnsLeft: turns)
            var f = state.sides[defender.rawValue].team[dIdx]
            f.trappedTurns = max(f.trappedTurns, turns)
            state.sides[defender.rawValue].team[dIdx] = f
            say("\(g.ko)가 상대를 휘감았다! (\(turns)턴)")

        case .hazard(let h):
            // 상대 진영에 설치 — 상대의 다음 포켓몬이 등장할 때 피해를 받는다
            state.sides[defender.rawValue].hazards.insert(h)
            say("상대 진영에 \(h.ko)가 깔렸다!")

        case .clearOwnHazards:
            let had = state.sides[attacker.rawValue].hazards
            guard !had.isEmpty else {
                say("\(g.ko)! 하지만 치울 것이 없었다.")
                break
            }
            state.sides[attacker.rawValue].hazards.removeAll()
            say("\(g.ko)로 \(had.map(\.ko).sorted().joined(separator: "·"))를 날려버렸다!")

        case .gravity(let turns):
            state.field.setGravity(turns)
            say("중력이 강해졌다! (\(turns)턴)")

        case .trap(let turns):
            var f = state.sides[defender.rawValue].team[dIdx]
            guard !f.isFainted else { break }
            f.trappedTurns = max(f.trappedTurns, turns)
            state.sides[defender.rawValue].team[dIdx] = f
            say("\(f.name)는 도망칠 수 없게 되었다! (\(turns)턴)")

        case .torment:
            var f = state.sides[defender.rawValue].team[dIdx]
            guard !f.isFainted, !f.tormented else { break }
            f.tormented = true
            state.sides[defender.rawValue].team[dIdx] = f
            say("\(f.name)는 같은 기술을 연속으로 쓸 수 없게 되었다!")

        case .bypassProtect:
            // 방어 관통은 데미지 판정 시점에 이미 적용된다 (여기서는 로그만)
            say("\(g.ko)는 방어를 뚫는다!")
        }
    }

    /// 확률 없이 확정으로 상태이상을 건다 (G-Max 전용기용). 면역은 그대로 존중한다.
    private mutating func inflictDirect(_ ail: Ailment, on side: BattleSide, source: String) {
        let idx = state.side(side).activeIndex
        guard state.side(side).team.indices.contains(idx) else { return }
        var t = state.sides[side.rawValue].team[idx]
        guard !t.isFainted else { return }

        if ail == .confusion {
            guard t.confusionTurns == 0 else { return }
            if state.rules.abilities, case .statusImmunity(.confusion) = t.abilityKind { return }
            t.confusionTurns = Int.random(in: 2...5, using: &rng)
            say("\(KO.t(t.name)) 혼란에 빠졌다!")
        } else {
            guard t.status == .none else { return }
            if state.rules.abilities, case .statusImmunity(let imm) = t.abilityKind,
               imm == ail || (imm == .poison && ail == .toxic) { return }
            if ail == .burn, t.types.contains(.fire) { return }
            if ail == .paralysis, t.types.contains(.electric) { return }
            if ail == .poison || ail == .toxic,
               t.types.contains(.poison) || t.types.contains(.steel) { return }
            t.status = ail
            if ail == .sleep { t.sleepTurns = Int.random(in: 2...4, using: &rng) }
            say("\(KO.t(t.name)) \(ail.ko) 상태가 되었다!")
        }
        state.sides[side.rawValue].team[idx] = t
    }

    private func isMagicGuard(_ b: Battler) -> Bool {
        if case .magicGuard = b.abilityKind { return true }
        return false
    }

    private mutating func lockChoiceMove(_ side: BattleSide, moveIndex: Int) {
        guard state.rules.itemEffects else { return }
        var b = state.side(side).active
        guard case .choice = b.itemKind, b.lockedMoveIndex == nil else { return }
        b.lockedMoveIndex = moveIndex
        state.sides[side.rawValue].team[state.side(side).activeIndex] = b
    }

    /// 쓴 쪽을 쓰러뜨린다 (대폭발 계열).
    private mutating func applySelfKO(_ side: BattleSide) {
        var b = state.side(side).active
        guard !b.isFainted else { return }
        b.currentHP = 0
        state.sides[side.rawValue].team[state.side(side).activeIndex] = b
        checkFaint(side)
    }

    /// 잠듦·얼음·마비·풀죽음·혼란으로 행동이 막히는지
    private mutating func checkPreMoveBlock(_ b: inout Battler, side: BattleSide) -> String? {
        if b.mustFlinch {
            b.mustFlinch = false
            return "\(KO.t(b.name)) 풀이 죽어 움직일 수 없다!"
        }
        guard state.rules.statusEffects else { return nil }

        switch b.status {
        case .sleep:
            if b.sleepTurns > 0 {
                b.sleepTurns -= 1
                if b.sleepTurns == 0 {
                    b.status = .none
                    return "\(KO.t(b.name)) 잠에서 깨어났다!"
                }
                return "\(KO.t(b.name)) 쿨쿨 잠들어 있다."
            }
            b.status = .none
        case .freeze:
            if rng.chance(20) {
                b.status = .none
                return "\(b.name)의 얼음이 녹았다!"
            }
            return "\(KO.t(b.name)) 얼어붙어 움직일 수 없다!"
        case .paralysis:
            if rng.chance(25) { return "\(KO.t(b.name)) 몸이 굳어 움직일 수 없다!" }
        default: break
        }

        if b.confusionTurns > 0 {
            b.confusionTurns -= 1
            if rng.chance(33) {
                let selfHit = max(1, b.maxHP / 8)
                b.currentHP = max(0, b.currentHP - selfHit)
                return "\(KO.t(b.name)) 혼란에 빠져 자신을 공격했다!"
            }
        }
        return nil
    }

    private mutating func accuracyCheck(move: MoveDef, attacker: Battler, defender: Battler) -> Bool {
        // 노가드 — 양쪽 중 하나라도 있으면 반드시 명중
        if state.rules.abilities {
            if case .noGuard = attacker.abilityKind { return true }
            if case .noGuard = defender.abilityKind { return true }
        }
        guard let acc = move.accuracy else { return true }   // nil = 필중
        let mod = Battler.accEvaMultiplier(attacker.accuracyStage)
                / Battler.accEvaMultiplier(defender.evasionStage)
        var final = Int((Double(acc) * mod).rounded())
        // 중력 — 명중률 5/3 배
        if state.rules.weather, state.field.hasGravity {
            final = Int(Double(final) * 5.0 / 3.0)
        }
        // 모래숨기·눈숨기 — 해당 날씨에서 회피율 상승
        if state.rules.weather, state.field.hasWeather,
           case .weatherEvasion(let w) = defender.abilityKind, w == state.field.weather {
            final = Int(Double(final) * 0.8)
        }
        return rng.chance(max(1, min(100, final)))
    }

    private mutating func hitCount(_ move: MoveDef) -> Int {
        guard let lo = move.minHits, let hi = move.maxHits, hi > 1 else { return 1 }
        if lo == hi { return lo }
        // 원작 분포 근사: 2·3회가 흔하고 4·5회는 드물다
        let roll = Int.random(in: 1...8, using: &rng)
        switch roll {
        case 1...3: return min(hi, 2)
        case 4...6: return min(hi, 3)
        case 7: return min(hi, 4)
        default: return hi
        }
    }

    // MARK: 데미지 계산

    struct DamageResult { var damage: Int; var critical: Bool; var typeMultiplier: Double; var multiplier: Double }

    private mutating func computeDamage(move: MoveDef, attacker: BattleSide, defender: BattleSide) -> DamageResult {
        let a = state.side(attacker).active
        let d = state.side(defender).active
        let physical = move.damageClass == .physical

        // 위력 공식을 따르지 않는 기술들 — 타입 상성만 보고 고정값을 낸다
        switch move.specialDamage {
        case .none:
            break
        case .userCurrentHP, .userLevel, .fixed:
            let typeMult = chart.multiplier(attack: move.type, defenders: d.types)
            let raw: Int
            switch move.specialDamage {
            case .userCurrentHP: raw = a.currentHP
            case .userLevel:     raw = a.level
            case .fixed(let n):  raw = n
            case .none:          raw = 0
            }
            return DamageResult(damage: typeMult == 0 ? 0 : max(1, raw),
                                critical: false,
                                typeMultiplier: typeMult,
                                multiplier: typeMult)
        }

        let power = move.power ?? 0

        // 급소율: 기본 1/24(≈4%), 기술 보너스나 다이맥스태클로 올라간다
        var critPercent = 4
        if move.critRateBonus > 0 { critPercent = 12 }
        switch a.critStage {
        case 1: critPercent = max(critPercent, 12)
        case 2: critPercent = max(critPercent, 50)
        case 3...: critPercent = 100
        default: break
        }
        var critical = state.rules.criticalHits && rng.chance(critPercent)
        if state.rules.abilities, case .criticalImmunity = d.abilityKind { critical = false }

        // 급소는 공격측 하락 랭크와 방어측 상승 랭크를 무시한다
        // 천진: 상대의 능력치 변화를 무시한다
        let ignoreFoeStages = state.rules.abilities && { if case .unaware = a.abilityKind { return true }; return false }()

        func atkStat() -> Int {
            let s: Stat = physical ? .attack : .spAttack
            var v: Double
            if critical, (a.stages[s] ?? 0) < 0 {
                v = Double(a.stat(s))
                if s == .attack, a.status == .burn { v *= 0.5 }
            } else {
                v = Double(a.effective(s))
            }
            v *= offenseMultiplier(a, stat: s)
            return max(1, Int(v))
        }
        func defStat() -> Int {
            let s: Stat = physical ? .defense : .spDefense
            var v: Double
            if ignoreFoeStages {
                v = Double(d.stat(s))
            } else if critical, (d.stages[s] ?? 0) > 0 {
                v = Double(d.stat(s))
            } else {
                v = Double(d.effective(s))
            }
            v *= defenseMultiplier(d, stat: s)
            return max(1, Int(v))
        }

        let A = Double(atkStat()), D = Double(defStat())
        let lvl = Double(a.level)

        // 원작 공식
        var dmg = floor(floor(floor(2.0 * lvl / 5.0 + 2.0) * Double(power) * A / D) / 50.0) + 2.0

        var typeMult = chart.multiplier(attack: move.type, defenders: d.types)

        // 특성: 배짱 — 노말/격투가 고스트에게 통한다
        if state.rules.abilities, case .scrappy = a.abilityKind,
           typeMult == 0, move.type == .normal || move.type == .fighting,
           d.types.contains(.ghost) {
            typeMult = chart.multiplier(attack: move.type,
                                        defenders: d.types.filter { $0 != .ghost })
            if d.types.allSatisfy({ $0 == .ghost }) { typeMult = 1.0 }
        }
        // 틀깨기 — 상대 특성을 무시한다
        let ignoreFoeAbility = state.rules.abilities
            && { if case .ignoreAbility = a.abilityKind { return true }; return false }()
        let foeAbility: AbilityKind = ignoreFoeAbility ? .none : d.abilityKind

        // 특성: 부유 등 타입 무효 — 단 중력 중에는 무효가 사라진다
        let gravityOn = state.rules.weather && state.field.hasGravity
        if state.rules.abilities, case .typeImmunity(let t) = foeAbility, move.type == t, !gravityOn {
            typeMult = 0
        }
        // 중력 중에는 땅 기술이 비행 타입에게도 통한다
        if gravityOn, move.type == .ground, d.types.contains(.flying) {
            let without = d.types.filter { $0 != .flying }
            typeMult = without.isEmpty ? 1.0 : chart.multiplier(attack: .ground, defenders: without)
        }
        // 타입 흡수 계열 (저수·축전·타오르는불꽃·건조피부)
        if state.rules.abilities, case .levitateLike(let t, let mult) = foeAbility, move.type == t {
            typeMult *= mult
        }
        if state.rules.abilities, case .dryskin = foeAbility {
            if move.type == .water { typeMult = 0 }
            if move.type == .fire { typeMult *= 1.25 }
        }

        // 자기 타입 일치 — 적응력이면 2.0
        var stabMult = 1.0
        if a.types.contains(move.type) {
            if state.rules.abilities, case .adaptability(let m) = a.abilityKind { stabMult = m }
            else { stabMult = 1.5 }
        }

        // 급소 — 스나이퍼면 2.25
        var critMult = 1.0
        if critical {
            if state.rules.abilities, case .sniper(let m) = a.abilityKind { critMult = m }
            else { critMult = 1.5 }
        }

        let rand = Double(Int.random(in: 85...100, using: &rng)) / 100.0
        var extra = 1.0

        if state.rules.abilities {
            // 궁지 강화 (맹화·급류·신록·벌레의야망)
            if case .pinchBoost(let t, let m) = a.abilityKind,
               move.type == t, a.currentHP * 3 <= a.maxHP { extra *= m }
            // 테크니션
            if case .technician(let cap, let m) = a.abilityKind,
               (move.power ?? 0) <= cap { extra *= m }
            // 우격다짐
            if case .sheerForce(let m) = a.abilityKind, hasSecondary(move) { extra *= m }
            // 색안경
            if case .tintedLens(let m) = a.abilityKind, typeMult > 0, typeMult < 1 { extra *= m }
            // 이판사판 (반동기)
            if case .reckless(let m) = a.abilityKind, move.drainPercent < 0 { extra *= m }

            // 기술 종류 강화 (철주먹·옹골찬턱·펑크록·강한발톱)
            if case .moveFlagBoost(let flag, let m) = a.abilityKind {
                let matches: Bool
                switch flag {
                case .punch:   matches = MoveFlags.isPunch(move.name)
                case .bite:    matches = MoveFlags.isBite(move.name)
                case .sound:   matches = MoveFlags.isSound(move.name)
                case .powder:  matches = MoveFlags.isPowder(move.name)
                case .contact: matches = MoveFlags.isContact(move.name)
                }
                if matches { extra *= m }
            }
            // 날씨에서 공격력 상승 (태양의힘·모래의힘)
            if state.rules.weather, state.field.hasWeather,
               case .weatherStatBoost(let w, let st, let m) = a.abilityKind,
               w == state.field.weather,
               (st == .attack && physical) || (st == .spAttack && !physical) { extra *= m }

            // 방어측 특성
            if case .damageTaken(let types, let m) = foeAbility, types.contains(move.type) { extra *= m }
            if case .superEffectiveResist(let m) = foeAbility, typeMult >= 2 { extra *= m }
            // 멀티스케일 — 풀피에서 받는 피해 감소
            if case .multiscale(let m) = foeAbility, d.currentHP == d.maxHP { extra *= m }
        }

        // 날씨 — 불꽃/물 기술 배율
        if state.rules.weather, state.field.hasWeather {
            extra *= state.field.weather.damageMultiplier(for: move.type)
        }
        // 필드 — 해당 타입 강화
        if state.rules.weather, state.field.hasTerrain {
            extra *= state.field.terrain.boost(for: move.type)
        }

        if state.rules.itemEffects {
            // 공격측 도구
            switch a.itemKind {
            case .lifeOrb:                        extra *= 1.3
            case .expertBelt where typeMult >= 2: extra *= 1.2
            case .classBoost(let cls, let m) where cls == move.damageClass: extra *= m
            case .typePlate(let t, let m) where t == move.type: extra *= m
            default: break
            }
        }

        let total = typeMult * stabMult * critMult * rand * extra
        dmg = floor(dmg * total)

        return DamageResult(damage: typeMult == 0 ? 0 : max(1, Int(dmg)),
                            critical: critical && typeMult != 0,
                            typeMultiplier: typeMult,
                            multiplier: total)
    }

    /// 공격 스탯에 붙는 도구·특성 배율
    private func offenseMultiplier(_ b: Battler, stat: Stat) -> Double {
        var m = 1.0
        if state.rules.abilities {
            if case .attackMultiplier(let x) = b.abilityKind, stat == .attack { m *= x }
            if case .statusAtkBoost(let s, let x) = b.abilityKind,
               s == stat, b.status != .none, b.status != .sleep, b.status != .freeze { m *= x }
        }
        if state.rules.itemEffects {
            if case .choice(let s) = b.itemKind, s == stat, s != .speed { m *= 1.5 }
        }
        return m
    }

    /// 방어 스탯에 붙는 도구·특성 배율
    private func defenseMultiplier(_ b: Battler, stat: Stat) -> Double {
        var m = 1.0
        if state.rules.abilities {
            if case .statusDefBoost(let s, let x) = b.abilityKind, s == stat, b.status != .none { m *= x }
        }
        if state.rules.itemEffects {
            if case .eviolite = b.itemKind, !b.fullyEvolved,
               stat == .defense || stat == .spDefense { m *= 1.5 }
            if case .assaultVest = b.itemKind, stat == .spDefense { m *= 1.5 }
        }
        return m
    }

    /// 부가효과(상태이상·랭크변화·풀죽음) 가 붙은 기술인가 — 우격다짐 판정에 쓴다
    private func hasSecondary(_ m: MoveDef) -> Bool {
        (m.ailment != .none && m.ailmentChance > 0 && m.ailmentChance < 100)
            || (!m.statChanges.isEmpty && m.statChangeChance < 100)
            || m.flinchChance > 0
    }

    /// 실제로 깎인 양을 돌려준다 (흡수 계산에 필요).
    /// 옹골참(특성) 과 기합의띠(도구) 는 풀피에서 받는 일격을 1 HP 로 버티게 한다.
    private mutating func applyDamage(_ amount: Int, to side: BattleSide) -> Int {
        var b = state.side(side).active
        var amount = amount

        let atFullHP = b.currentHP == b.maxHP
        if amount >= b.currentHP, atFullHP {
            var survived = false
            if state.rules.abilities, case .sturdy = b.abilityKind {
                survived = true
                say("\(b.name)는 옹골참으로 버텼다!")
            } else if state.rules.itemEffects, case .focusSash = b.itemKind {
                survived = true
                b.itemConsumed = true
                say("\(b.name)는 기합의띠로 버텼다!")
            }
            if survived { amount = b.currentHP - 1 }
        }

        let dealt = min(b.currentHP, amount)
        b.currentHP -= dealt
        state.sides[side.rawValue].team[state.side(side).activeIndex] = b
        return dealt
    }

    // MARK: 변화기 / 부가효과

    private mutating func applyNonDamaging(move: MoveDef, attacker: BattleSide, defender: BattleSide) {
        var acted = false

        // 날씨 / 필드 기술 — PokeAPI 는 whole-field-effect 라고만 알려주므로 이름으로 판정한다
        if state.rules.weather {
            if let w = Weather.from(moveName: move.name) {
                state.field.setWeather(w, turns: 5)
                say("\(w.ko) 상태가 되었다!")
                acted = true
            }
            if let t = Terrain.from(moveName: move.name) {
                state.field.setTerrain(t, turns: 5)
                say("\(t.ko)가 깔렸다!")
                acted = true
            }
        }

        // 회복기
        if move.healingPercent > 0 {
            var a = state.side(attacker).active
            let heal = max(1, a.maxHP * move.healingPercent / 100)
            if a.currentHP >= a.maxHP {
                say("\(a.name)의 체력은 가득 차 있다!")
            } else {
                a.currentHP = min(a.maxHP, a.currentHP + heal)
                say("\(KO.t(a.name)) 체력을 회복했다!")
            }
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a
            acted = true
        }

        if applyStatus(move: move, attacker: attacker, defender: defender, guaranteed: true) { acted = true }
        if applyStatStages(move: move, attacker: attacker, defender: defender, guaranteed: true) { acted = true }

        if !acted { say("하지만 아무 일도 일어나지 않았다!") }
    }

    private mutating func applySecondary(move: MoveDef, attacker: BattleSide, defender: BattleSide) {
        _ = applyStatus(move: move, attacker: attacker, defender: defender, guaranteed: false)
        _ = applyStatStages(move: move, attacker: attacker, defender: defender, guaranteed: false)

        if move.flinchChance > 0, rng.chance(move.flinchChance) {
            var d = state.side(defender).active
            d.mustFlinch = true
            state.sides[defender.rawValue].team[state.side(defender).activeIndex] = d
        }
    }

    private mutating func applyStatus(move: MoveDef, attacker: BattleSide, defender: BattleSide, guaranteed: Bool) -> Bool {
        guard state.rules.statusEffects, move.ailment != .none, move.ailment != .unknown else { return false }
        var chance = guaranteed ? max(move.ailmentChance, 100) : move.ailmentChance
        if state.rules.abilities, !guaranteed,
           case .sereneGrace(let m) = state.side(attacker).active.abilityKind {
            chance = min(100, Int(Double(chance) * m))
        }
        guard rng.chance(chance) else { return false }

        let target: BattleSide = move.targetsSelf ? attacker : defender
        var t = state.side(target).active

        if move.ailment == .confusion {
            if state.rules.abilities, case .statusImmunity(.confusion) = t.abilityKind {
                say("\(KO.t(t.name)) \(t.ability?.display ?? "특성") 때문에 혼란에 빠지지 않는다!")
                return false
            }
            guard t.confusionTurns == 0 else { say("\(KO.t(t.name)) 이미 혼란 상태다!"); return false }
            t.confusionTurns = Int.random(in: 2...5, using: &rng)
            say("\(KO.t(t.name)) 혼란에 빠졌다!")
        } else {
            guard t.status == .none else { return false }
            // 특성 면역 (면역·수의베일·불면·유연 등)
            if state.rules.abilities, case .statusImmunity(let imm) = t.abilityKind,
               imm == move.ailment || (imm == .poison && move.ailment == .toxic) {
                say("\(t.name)는 \(t.ability?.display ?? "특성") 때문에 \(move.ailment.ko) 상태가 되지 않는다!")
                return false
            }
            // 타입 면역 (원작 규칙)
            if move.ailment == .burn, t.types.contains(.fire) { return false }
            if move.ailment == .freeze, t.types.contains(.ice) { return false }
            if move.ailment == .paralysis, t.types.contains(.electric) { return false }
            if (move.ailment == .poison || move.ailment == .toxic),
               t.types.contains(.poison) || t.types.contains(.steel) { return false }

            t.status = move.ailment
            if move.ailment == .sleep { t.sleepTurns = Int.random(in: 2...4, using: &rng) }
            if move.ailment == .toxic { t.toxicCounter = 1 }
            say("\(KO.t(t.name)) \(move.ailment.ko) 상태가 되었다!")
        }
        state.sides[target.rawValue].team[state.side(target).activeIndex] = t
        return true
    }

    private mutating func applyStatStages(move: MoveDef, attacker: BattleSide, defender: BattleSide, guaranteed: Bool) -> Bool {
        guard state.rules.statStages, !move.statChanges.isEmpty else { return false }
        let chance = guaranteed ? max(move.statChangeChance, 100) : move.statChangeChance
        guard rng.chance(chance) else { return false }

        let target: BattleSide = move.targetsSelf ? attacker : defender
        var t = state.side(target).active
        var changed = false

        // 클리어바디 계열 — 상대가 걸어오는 능력치 하락을 막는다
        if state.rules.abilities, target != attacker,
           case .clearBody = t.abilityKind, move.statChanges.contains(where: { $0.change < 0 }) {
            say("\(t.name)는 \(t.ability?.display ?? "특성") 때문에 능력치가 떨어지지 않는다!")
            return false
        }
        // 색가루 — 부가효과를 받지 않는다
        if state.rules.abilities, target != attacker, !guaranteed,
           case .shieldDust = t.abilityKind { return false }

        for c in move.statChanges {
            let cur = t.stages[c.stat] ?? 0
            let next = max(-6, min(6, cur + c.change))
            if next == cur {
                say("\(t.name)의 \(KO.t(c.stat.ko)) 더 이상 \(c.change > 0 ? "올라가지" : "떨어지지") 않는다!")
                continue
            }
            t.stages[c.stat] = next
            changed = true
            let mag = abs(c.change)
            let word = c.change > 0 ? (mag >= 2 ? "크게 올라갔다" : "올라갔다")
                                    : (mag >= 2 ? "크게 떨어졌다" : "떨어졌다")
            say("\(t.name)의 \(KO.s(c.stat.ko)) \(word)!")
        }
        state.sides[target.rawValue].team[state.side(target).activeIndex] = t
        return changed
    }

    // MARK: 턴 종료

    private mutating func endOfTurn() {
        guard state.rules.statusEffects else { tickDynamax(); checkBattleOver(); return }

        for s in [BattleSide.host, .guest] {
            var b = state.side(s).active
            guard !b.isFainted else { continue }

            // 아이스바디·우비 — 해당 날씨에서 회복
            if state.rules.weather, state.rules.abilities, state.field.hasWeather,
               case .weatherHeal(let w, let denom) = b.abilityKind,
               w == state.field.weather, b.currentHP < b.maxHP {
                b.currentHP = min(b.maxHP, b.currentHP + max(1, b.maxHP / denom))
                say("\(KO.t(b.name)) \(b.ability?.display ?? "특성")(으)로 체력을 회복했다!")
            }

            // 먹다남은음식 — 최대 HP 1/16 회복
            if state.rules.itemEffects, case .leftovers = b.itemKind, b.currentHP < b.maxHP {
                b.currentHP = min(b.maxHP, b.currentHP + max(1, b.maxHP / 16))
                say("\(KO.t(b.name)) 먹다남은음식으로 체력을 회복했다!")
            }
            // 화염구슬 / 맹독구슬 — 자신에게 상태이상
            if state.rules.itemEffects, case .selfStatusOrb(let ail) = b.itemKind, b.status == .none {
                b.status = ail
                if ail == .toxic { b.toxicCounter = 1 }
                say("\(KO.t(b.name)) \(b.heldItem?.display ?? "도구") 때문에 \(ail.ko) 상태가 되었다!")
            }

            // 매직가드 — 간접 피해를 받지 않는다
            if state.rules.abilities, isMagicGuard(b) {
                state.sides[s.rawValue].team[state.side(s).activeIndex] = b
                continue
            }

            switch b.status {
            case .burn:
                let d = max(1, b.maxHP / 16)
                b.currentHP = max(0, b.currentHP - d)
                say("\(KO.t(b.name)) 화상 때문에 데미지를 받았다!")
            case .poison:
                let d = max(1, b.maxHP / 8)
                b.currentHP = max(0, b.currentHP - d)
                say("\(KO.t(b.name)) 독 때문에 데미지를 받았다!")
            case .toxic:
                let d = max(1, b.maxHP * b.toxicCounter / 16)
                b.currentHP = max(0, b.currentHP - d)
                b.toxicCounter = min(15, b.toxicCounter + 1)
                say("\(KO.t(b.name)) 맹독 때문에 데미지를 받았다!")
            default: break
            }
            state.sides[s.rawValue].team[state.side(s).activeIndex] = b
            checkFaint(s)
        }
        tickWeatherAndField()
        tickGMaxDoT()
        tickDynamax()
        checkBattleOver()
    }

    /// 모래바람 지속 피해와 날씨·필드 지속시간
    private mutating func tickWeatherAndField() {
        guard state.rules.weather else { return }

        if state.field.hasWeather, state.field.weather == .sandstorm {
            for side in [BattleSide.host, .guest] {
                var b = state.side(side).active
                guard !b.isFainted else { continue }
                if state.field.weather.isImmuneToChip(b.types) { continue }
                if state.rules.abilities, isMagicGuard(b) { continue }
                b.currentHP = max(0, b.currentHP - max(1, b.maxHP / 16))
                state.sides[side.rawValue].team[state.side(side).activeIndex] = b
                say("\(KO.t(b.name)) 모래바람에 시달리고 있다!")
                checkFaint(side)
            }
        }

        let ended = state.field.tick()
        if let w = ended.endedWeather { say("\(w.ko)이(가) 그쳤다!") }
        if let t = ended.endedTerrain { say("\(t.ko)가 사라졌다!") }
        if ended.gravityEnded { say("중력이 원래대로 돌아왔다!") }

        // 조임 지속시간 감소
        for side in [BattleSide.host, .guest] {
            let i = state.side(side).activeIndex
            guard state.side(side).team.indices.contains(i) else { continue }
            var b = state.sides[side.rawValue].team[i]
            guard b.trappedTurns > 0 else { continue }
            b.trappedTurns -= 1
            if b.trappedTurns == 0 { say("\(KO.t(b.name)) 자유로워졌다!") }
            state.sides[side.rawValue].team[i] = b
        }
    }

    /// G-Max 지속 피해 (다이맥스채찍·다이맥스파이어 등)
    private mutating func tickGMaxDoT() {
        for side in [BattleSide.host, .guest] {
            guard var dot = state.gmaxDoT[side.rawValue] else { continue }
            var b = state.side(side).active
            if !b.isFainted, !b.types.contains(dot.immuneType) {
                if !(state.rules.abilities && isMagicGuard(b)) {
                    b.currentHP = max(0, b.currentHP - max(1, b.maxHP / 6))
                    state.sides[side.rawValue].team[state.side(side).activeIndex] = b
                    say("\(KO.t(b.name)) 거다이맥스 기술의 여파로 피해를 입었다!")
                    checkFaint(side)
                }
            }
            dot.turnsLeft -= 1
            if dot.turnsLeft <= 0 { state.gmaxDoT[side.rawValue] = nil }
            else { state.gmaxDoT[side.rawValue] = dot }
        }
    }

    private mutating func checkFaint(_ side: BattleSide) {
        let b = state.side(side).active
        guard b.isFainted else { return }
        // 같은 종이 여러 마리일 수 있으므로 직전 로그와만 중복을 막는다
        let marker = "\(KO.t(b.name)) 쓰러졌다!"
        if state.log.last != marker { say(marker) }
        checkBattleOver()
    }

    private mutating func checkBattleOver() {
        if case .finished = state.phase { return }
        let h = state.side(.host).remaining
        let g = state.side(.guest).remaining
        guard h == 0 || g == 0 else { return }

        if h == 0 && g == 0 {
            say("무승부!")
            state.phase = .finished(winner: nil)
        } else if g == 0 {
            say("\(state.side(.host).playerName) 승리!")
            state.phase = .finished(winner: BattleSide.host.rawValue)
        } else {
            say("\(state.side(.guest).playerName) 승리!")
            state.phase = .finished(winner: BattleSide.guest.rawValue)
        }
    }
}
