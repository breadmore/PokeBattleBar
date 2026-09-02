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

    func side(_ s: BattleSide) -> SideState { sides[s.rawValue] }
}

// MARK: - 행동

enum BattleAction: Codable, Sendable, Equatable {
    /// 기술을 쓴다. `special` 은 이번 턴에 함께 선언하는 특수 변신
    /// (원작처럼 기술 선택과 같은 시점에 선언한다).
    case useMove(index: Int, special: SpecialAction? = nil)
    case replace(teamIndex: Int)

    var moveIndex: Int? {
        if case .useMove(let i, _) = self { return i }
        return nil
    }
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

    /// 등장 시 발동하는 특성 (위협)
    private mutating func fireEntryAbility(_ side: BattleSide) {
        guard state.rules.abilities else { return }
        let idx = state.side(side).activeIndex
        guard state.side(side).team.indices.contains(idx) else { return }
        var b = state.sides[side.rawValue].team[idx]
        guard !b.entryAbilityFired, !b.isFainted else { return }
        b.entryAbilityFired = true
        state.sides[side.rawValue].team[idx] = b

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
                if mv.indices.contains(i) { return mv[i].def.priority }
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

        // 명중 판정
        let def = state.side(defender).active
        if !accuracyCheck(move: move, attacker: atk, defender: def) {
            say("\(atkName)의 공격은 빗나갔다!")
            return
        }

        // 변화기 (고정 데미지 기술은 위력이 0 이어도 공격기다)
        if move.damageClass == .status || !move.isDamaging {
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
        guard zDeclared.contains(attacker.rawValue),
              let zName = FormTables.zMoveName(for: move),
              var z = zMoveCache[zName] else { return move }
        z.power = FormTables.zPower(basePower: move.power ?? 0)
        z.damageClass = move.damageClass
        z.accuracy = nil                           // Z기술은 필중
        z.specialDamage = .none
        z.selfKO = false
        return z
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
        let final = Int((Double(acc) * mod).rounded())
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

        let critical = state.rules.criticalHits && rng.chance(move.critRateBonus > 0 ? 12 : 4)

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
        // 특성: 부유 등 타입 무효
        if state.rules.abilities, case .typeImmunity(let t) = d.abilityKind, move.type == t {
            typeMult = 0
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

            // 방어측 특성
            if case .damageTaken(let types, let m) = d.abilityKind, types.contains(move.type) { extra *= m }
            if case .superEffectiveResist(let m) = d.abilityKind, typeMult >= 2 { extra *= m }
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
        tickDynamax()
        checkBattleOver()
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
