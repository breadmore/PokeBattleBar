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

    // MARK: 게임 모드 (각각 독립 토글 — 조합해서 쓸 수 있다)

    /// 랜덤 기술 모드 — 저장된 기술 대신 **배틀마다 새로 뽑은** 기술 4개로 싸운다.
    var randomMoveset: Bool = false
    /// 자유의지 모드 — 플레이어가 고르지 않고 보유한 4개 중 무작위로 쓴다.
    var autoMove: Bool = false
    /// 변신 자동 선언 — 도구를 끼웠다면 메가진화·다이맥스·Z기술을 무작위 시점에 발동한다.
    var autoSpecial: Bool = false
    /// 토게피 손가락흔들기 1:1 모드.
    /// 양쪽 모두 토게피 1마리(보유 여부 무관), 기술은 손가락흔들기 하나, PP 최대치,
    /// 생명의구슬 장착. 다른 팀 설정은 무시된다.
    var metronomeMode: Bool = false

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
    case awaitingReplacement([Int])       // 쓰러져서 교체가 필요한 side raw 값들
    /// 유턴 계열로 **스스로 물러나는** 경우. 쓰러진 게 아니라 살아서 교체한다.
    case awaitingPivot([Int])
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
    /// 이번 턴 유턴 계열을 써서 물러나야 하는 진영
    var pendingPivot: Set<Int> = []
    /// 이번 턴을 순서대로 재생하기 위한 스냅샷.
    /// 결과만 보여주면 무슨 일이 있었는지 알 수 없어서, 단계별 HP·로그를 남긴다.
    var steps: [TurnStep] = []

    func side(_ s: BattleSide) -> SideState { sides[s.rawValue] }
}

// MARK: - 행동

/// 턴을 순서대로 재생하기 위한 한 단계.
/// 로그와 그 시점의 HP·활성 인덱스를 담는다.
struct TurnStep: Codable, Sendable, Equatable {
    var log: [String]
    var hostHP: [Int]
    var guestHP: [Int]
    var hostActive: Int
    var guestActive: Int
}

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
    /// 폼 종족값 캐시 (캐스퐁·불비달마 자동 변신, 로토무 등 사전 선택 폼)
    var formCache: [String: FormStats] = [:]
    /// 손가락흔들기가 부를 수 있는 기술 풀.
    /// 배틀 중엔 네트워크를 쓸 수 없으므로 미리 채워 넣는다.
    var metronomePool: [MoveDef] = []

    init(state: BattleState, chart: TypeChart, seed: UInt64) {
        self.state = state
        self.chart = chart
        self.rng = SeededRNG(seed: seed)
    }

    private mutating func say(_ s: String) { state.log.append(s) }

    /// 이번 턴이 시작될 때의 로그 길이. mark() 가 이 지점 이후만 잘라내야 한다.
    /// 이걸 안 쓰고 steps 합계만 보면, 턴 시작에 steps 를 비운 뒤 첫 mark() 가
    /// **배틀 전체 로그**를 한 단계에 담아버린다.
    private var stepLogBase = 0

    /// 지금까지 쌓인 로그를 한 단계로 끊어 기록한다.
    /// UI 가 이 단계들을 순서대로 재생해서 "누가 먼저 때렸는지" 를 보여준다.
    private mutating func mark() {
        let already = stepLogBase + state.steps.reduce(0) { $0 + $1.log.count }
        let newLines = Array(state.log.dropFirst(already))
        guard !newLines.isEmpty else { return }
        state.steps.append(TurnStep(
            log: newLines,
            hostHP: state.sides[0].team.map(\.currentHP),
            guestHP: state.sides[1].team.map(\.currentHP),
            hostActive: state.sides[0].activeIndex,
            guestActive: state.sides[1].activeIndex))
    }

    // MARK: 선봉 확정

    /// 선봉을 정한다. 범위를 벗어난 인덱스를 **조용히 무시하면** activeIndex 가 0 에 남아
    /// "고른 포켓몬이 아니라 맨 왼쪽이 나온다"가 된다. 그래서 클램프하고 흔적을 남긴다.
    /// 재생용 스텝을 비운다.
    ///
    /// UI 는 `state.steps` 가 비어 있으면 "재생할 새 사건이 없다" 로 보고
    /// 바로 다음 화면을 열고, 비어 있지 않으면 그것을 순서대로 재생한다.
    /// 그래서 **턴이 아닌 조작**(교체·피벗·선봉 지정)에서 비우지 않으면
    /// 직전 턴이 통째로 다시 재생된다 — 방금 쓰러진 포켓몬이 한 번 더
    /// 쓰러지는 연출로 보이던 것이 이것이다.
    private mutating func clearSteps() {
        state.steps = []
        stepLogBase = state.log.count
    }

    mutating func setLead(_ side: BattleSide, index: Int) {
        clearSteps()
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
        clearSteps()
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
        applySwitchOutAbility(&out)
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

        // 트레이스 — 상대 특성을 복사한다
        if case .trace = b.abilityKind {
            let fIdx = state.side(side.other).activeIndex
            if state.side(side.other).team.indices.contains(fIdx),
               let foeAb = state.side(side.other).team[fIdx].ability,
               foeAb.isImplemented {
                var me = state.sides[side.rawValue].team[idx]
                me.ability = foeAb
                state.sides[side.rawValue].team[idx] = me
                say("\(me.name)는 트레이스로 \(foeAb.display)을(를) 복사했다!")
                // 복사한 특성이 등장 효과라면 그것도 발동시킨다
                me.entryAbilityFired = false
                state.sides[side.rawValue].team[idx] = me
                fireEntryAbility(side)
                return
            }
        }

        // 다운로드 — 상대의 약한 방어 쪽을 노려 능력이 오른다
        if case .download = b.abilityKind {
            let fIdx = state.side(side.other).activeIndex
            if state.side(side.other).team.indices.contains(fIdx) {
                let f = state.side(side.other).team[fIdx]
                let stat: Stat = f.effective(.defense) <= f.effective(.spDefense) ? .attack : .spAttack
                var me = state.sides[side.rawValue].team[idx]
                let cur = me.stages[stat] ?? 0
                if cur < 6 {
                    me.stages[stat] = min(6, cur + 1)
                    state.sides[side.rawValue].team[idx] = me
                    say("\(me.name)의 다운로드! \(KO.s(stat.ko)) 올라갔다!")
                }
            }
        }

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

        state.pendingPivot = []
        // 재생용 스텝을 새로 쌓는다 (직전 턴 것은 UI 가 이미 소비했다)
        clearSteps()

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
        applyAutoForms()
        mark()          // 변신을 별도 단계로 보여준다

        let order = turnOrder(hostAction: hostAction, guestAction: guestAction)

        for side in order {
            if case .finished = state.phase { break }
            // 이미 쓰러진 포켓몬은 행동하지 않는다
            if state.side(side).active.isFainted { continue }
            let action = side == .host ? hostAction : guestAction
            if let idx = action.moveIndex {
                performMove(attacker: side, moveIndex: idx)
                mark()          // 한 쪽이 때린 직후를 한 단계로
            }
        }

        if case .finished = state.phase { return }

        endOfTurn()
        mark()          // 턴 종료 처리(상태이상·날씨·열매) 를 한 단계로

        if case .finished = state.phase { return }

        // 쓰러진 쪽은 다음 포켓몬을 골라야 한다 (교체 없음 — 쓰러져야 등장)
        advancePhaseAfterTurn()
    }

    /// 턴이 끝난 뒤 다음 단계를 정한다.
    /// 쓰러진 쪽의 교체가 먼저고, 그다음이 유턴 계열의 자발적 후퇴다.
    private mutating func advancePhaseAfterTurn() {
        var needs: [Int] = []
        for s in [BattleSide.host, .guest] where state.side(s).active.isFainted {
            needs.append(s.rawValue)
            state.pendingPivot.remove(s.rawValue)   // 쓰러졌으면 피벗은 무의미
        }
        if !needs.isEmpty {
            state.phase = .awaitingReplacement(needs)
            return
        }
        // 낼 수 있는 포켓몬이 남아 있어야 물러날 수 있다
        let pivots = state.pendingPivot.filter { raw in
            guard let s = BattleSide(rawValue: raw) else { return false }
            return state.side(s).aliveIndices.contains { $0 != state.side(s).activeIndex }
        }
        if !pivots.isEmpty {
            state.pendingPivot = pivots
            state.phase = .awaitingPivot(pivots.sorted())
            return
        }
        state.pendingPivot = []
        state.turn += 1
        state.phase = .awaitingMoves
    }

    /// 물러나는 포켓몬에게 붙는 특성 (자연회복·재생력)
    private mutating func applySwitchOutAbility(_ b: inout Battler) {
        guard state.rules.abilities else { return }
        switch b.abilityKind {
        case .cureOnSwitch:
            if b.status != .none {
                say("\(KO.t(b.name)) 자연회복으로 상태이상이 나았다!")
                b.status = .none; b.sleepTurns = 0; b.toxicCounter = 0
            }
        case .healOnEntry:
            if b.currentHP > 0, b.currentHP < b.maxHP {
                b.currentHP = min(b.maxHP, b.currentHP + max(1, b.maxHP / 3))
                say("\(KO.t(b.name)) 재생력으로 체력을 회복했다!")
            }
        default:
            break
        }
    }

    /// 유턴 계열로 물러나 다른 포켓몬을 낸다. 쓰러진 게 아니므로 상태만 초기화한다.
    mutating func applyPivot(_ side: BattleSide, teamIndex: Int) {
        guard case .awaitingPivot(var pending) = state.phase,
              pending.contains(side.rawValue) else { return }
        clearSteps()
        let team = state.side(side).team
        let cur = state.side(side).activeIndex
        guard team.indices.contains(teamIndex), teamIndex != cur,
              !team[teamIndex].isFainted else { return }

        var out = team[cur]
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
        out.trappedTurns = 0
        out.trapMoveName = nil
        out.substituteHP = nil
        out.cursed = false
        out.encoreTurns = 0
        out.encoreMoveIndex = nil
        out.drowsyTurns = 0
        out.stockpile = 0
        out.consecutiveMoveIndex = nil
        out.consecutiveCount = 0
        out.magnetRiseTurns = 0
        out.cannotFlee = false
        out.chargingMoveIndex = nil
        out.chargeHidden = false
        out.mustRechargeTurns = 0
        if out.isDynamaxed { out.revertDynamax() }
        applySwitchOutAbility(&out)
        state.sides[side.rawValue].team[cur] = out
        state.gmaxDoT[side.rawValue] = nil

        state.sides[side.rawValue].activeIndex = teamIndex
        say("\(out.name)는 뒤로 물러났다! \(state.side(side).playerName): 가라, \(team[teamIndex].name)!")

        applyHazards(to: side)
        pending.removeAll { $0 == side.rawValue }
        state.pendingPivot.remove(side.rawValue)

        if state.side(side).active.isFainted {
            checkBattleOver()
            if case .finished = state.phase { return }
            state.phase = .awaitingReplacement([side.rawValue])
            return
        }
        fireEntryAbility(side)

        if pending.isEmpty {
            state.turn += 1
            state.phase = .awaitingMoves
        } else {
            state.phase = .awaitingPivot(pending)
        }
    }

    /// 쓰러진 자리에 다음 포켓몬을 낸다.
    mutating func applyReplacement(_ side: BattleSide, teamIndex: Int) {
        guard case .awaitingReplacement(var needs) = state.phase else { return }
        guard needs.contains(side.rawValue) else { return }
        clearSteps()
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
            // 쓰러진 자리를 다 채웠으면, 유턴으로 물러날 쪽이 남았는지 본다
            let pivots = state.pendingPivot.filter { raw in
                guard let s = BattleSide(rawValue: raw) else { return false }
                return !state.side(s).active.isFainted
                    && state.side(s).aliveIndices.contains { $0 != state.side(s).activeIndex }
            }
            if !pivots.isEmpty {
                state.pendingPivot = pivots
                state.phase = .awaitingPivot(pivots.sorted())
            } else {
                state.pendingPivot = []
                state.turn += 1
                state.phase = .awaitingMoves
            }
        } else {
            state.phase = .awaitingReplacement(needs)
        }
    }

    // MARK: 배틀 중 자동 폼 변신 (캐스퐁·불비달마·체리꼬·약어리)

    /// 특성 조건에 맞춰 폼을 바꾼다. HP 는 건드리지 않고 타입·종족값만 바뀐다.
    private mutating func applyAutoForms() {
        guard state.rules.abilities else { return }
        for side in [BattleSide.host, .guest] {
            let idx = state.side(side).activeIndex
            guard state.side(side).team.indices.contains(idx) else { continue }
            var b = state.sides[side.rawValue].team[idx]
            guard !b.isFainted,
                  let ab = b.ability?.name,
                  let rule = FormChange.autoRule(ability: ab, speciesID: b.speciesID) else { continue }

            let weather = state.rules.weather && state.field.hasWeather ? state.field.weather : Weather.none
            let ratio = Double(b.currentHP) / Double(max(1, b.maxHP))
            var want: String?

            switch rule {
            case .byWeather(let map, let base):
                want = map[weather] ?? base
            case .inSun(let f, let base):
                want = weather == .sun ? f : base
            case .belowHP(let t, let f, let base):
                want = ratio <= t ? f : base
            case .aboveHP(let t, let f, let base):
                want = ratio >= t ? f : base
            }

            guard let want, b.autoForm != want else { continue }
            let stats = formCache[want]
            guard stats != nil else { continue }   // 데이터가 없으면 바꾸지 않는다
            b.applyAutoForm(want, stats: stats, nature: Nature.named(natureOf(b)))
            state.sides[side.rawValue].team[idx] = b
            say("\(b.name)는 \(FormChange.label(want)) 폼으로 변했다!")
        }
    }

    // MARK: 자동 행동 (자유의지 / 변신 자동 선언)

    /// 자유의지 모드에서 그 진영의 행동을 무작위로 정한다.
    /// 호스트가 양쪽을 모두 굴려야 결과가 갈리지 않는다.
    mutating func autoAction(for side: BattleSide) -> BattleAction {
        let me = state.side(side)
        let b = me.active

        var special: SpecialAction?
        if state.rules.autoSpecial {
            var pool: [SpecialAction] = []
            if state.rules.allowMega, !me.usedMega,
               b.canMega(requiringItem: state.rules.requireItems) {
                let form = state.rules.requireItems ? b.megaFormFromItem : b.megaForms.first
                if let form { pool.append(.mega(form: form)) }
            }
            if state.rules.allowDynamax, !me.usedDynamax {
                if state.rules.allowGigantamax,
                   b.canGigantamax(requiringItem: state.rules.requireItems) {
                    pool.append(.gmax)
                }
                if b.canDynamax(requiringItem: state.rules.requireItems) {
                    pool.append(.dynamax)
                }
            }
            if state.rules.allowZMove, !me.usedZMove,
               b.canZMove(requiringItem: state.rules.requireItems) {
                pool.append(.zMove)
            }
            // 매 턴 확정 발동하면 첫 턴에 다 써버린다 — 무작위 시점에 터지게 한다
            if !pool.isEmpty, rng.chance(35) {
                special = pool.randomElement(using: &rng)
            }
        }

        // 구애로 고정됐으면 그 기술만 쓸 수 있다
        if let lock = b.lockedMoveIndex, b.moves.indices.contains(lock), b.moves[lock].usable {
            return .useMove(index: lock, special: special)
        }
        let usable = b.moves.indices.filter { b.moves[$0].usable }
        let idx = usable.randomElement(using: &rng) ?? 0
        return .useMove(index: idx, special: special)
    }

    /// 자유의지 모드에서 쓰러진 자리에 낼 포켓몬을 무작위로 정한다.
    mutating func autoReplacement(for side: BattleSide) -> Int? {
        state.side(side).aliveIndices.randomElement(using: &rng)
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

        // 특성 우선도 (짓궂은마음·질풍날개·굼뜸)
        if state.rules.abilities {
            func abilityPriority(_ side: BattleSide, _ a: BattleAction) -> Int {
                guard let i = a.moveIndex else { return 0 }
                let b = state.side(side).active
                guard b.moves.indices.contains(i) else { return 0 }
                let mv = b.moves[i].def
                guard case .priorityBoost(let cls, let n) = b.abilityKind else { return 0 }
                if let cls, mv.damageClass != cls { return 0 }
                if cls == nil, case .priorityBoost = b.abilityKind {
                    // 질풍날개는 비행 기술만, 트리아지는 회복기만 — 세부 조건은 타입으로 본다
                    if b.ability?.name == "gale-wings", mv.type != .flying { return 0 }
                    if b.ability?.name == "triage", mv.healingPercent <= 0 { return 0 }
                }
                return n
            }
            hp += abilityPriority(.host, hostAction)
            gp += abilityPriority(.guest, guestAction)

            // 선단 — 확률로 선공
            if case .quickDraw(let p) = state.side(.host).active.abilityKind, rng.chance(p) {
                say("\(state.side(.host).active.name)의 선단이 발동했다!"); hp += 1
            }
            if case .quickDraw(let p) = state.side(.guest).active.abilityKind, rng.chance(p) {
                say("\(state.side(.guest).active.name)의 선단이 발동했다!"); gp += 1
            }
        }

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
            if state.rules.abilities {
                // 속보 — 상태이상일 때 스피드 상승
                if case .statusSpeedBoost(let m) = b.abilityKind, b.status != .none { v *= m }
                // 곡예 — 도구를 다 쓰면 스피드 2배
                if case .unburden = b.abilityKind, b.itemConsumed { v *= 2.0 }
            }
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
                if state.rules.requireItems {
                    say("[안내] \(b.name)는 다이맥스 밴드를 지니고 있지 않습니다. (일반 다이맥스 전용 도구)")
                }
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
                    say("[안내] \(b.name)는 다이버섯을 지니고 있지 않습니다. (거다이맥스 전용 도구)")
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
            // 쓰러진 개체는 해제 처리에서 건드리지 않는다 (부활 방지)
            guard !b.isFainted else {
                b.revertDynamax()
                state.sides[side.rawValue].team[idx] = b
                continue
            }
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

    /// 모으던 기술을 이번 턴에 내보낸다
    private mutating func releaseChargedMove(attacker: BattleSide, moveIndex: Int) {
        performMove(attacker: attacker, moveIndex: moveIndex, skipCharge: true)
    }

    private mutating func performMove(attacker: BattleSide, moveIndex: Int,
                                      skipCharge: Bool = false) {
        let defender = attacker.other
        var atk = state.side(attacker).active
        let atkName = atk.name

        // 파괴광선 계열을 쓴 다음 턴은 움직일 수 없다
        if atk.mustRechargeTurns > 0 {
            atk.mustRechargeTurns -= 1
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = atk
            say("\(KO.t(atkName)) 반동으로 움직일 수 없다!")
            return
        }

        // 모으는 중이면 이번 턴에 그 기술이 나간다 (고른 기술은 무시된다)
        if let charging = atk.chargingMoveIndex {
            atk.chargingMoveIndex = nil
            atk.chargeHidden = false
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = atk
            releaseChargedMove(attacker: attacker, moveIndex: charging)
            return
        }

        guard atk.moves.indices.contains(moveIndex) else { return }
        // 쓸 수 있는 기술이 하나도 없으면 발버둥을 쓴다 (원작 규칙).
        // 이걸 안 하면 양쪽이 "PP가 없다" 만 반복해 배틀이 끝나지 않는다.
        if !atk.moves.contains(where: \.usable) {
            performStruggle(attacker: attacker, defender: defender)
            return
        }
        guard atk.moves[moveIndex].usable else {
            say("\(atkName)의 \(atk.moves[moveIndex].def.display)! …PP가 없다!")
            return
        }

        // 저주받은바디로 봉인된 기술은 쓸 수 없다
        if atk.disabledTurns > 0, atk.disabledMoveIndex == moveIndex {
            say("\(atkName)의 \(atk.moves[moveIndex].def.display)은(는) 봉인되어 있다!")
            return
        }

        // 아무것도않기 — 같은 기술을 연속으로 쓸 수 없다
        if atk.tormented, atk.lastMoveIndex == moveIndex {
            say("\(atkName)는 같은 기술을 연속으로 쓸 수 없다!")
            return
        }

        // 구애 계열로 고정됐으면 **그 기술로 바꿔서 쓴다.**
        //
        // 예전에는 안내만 하고 턴을 날렸다. 원작은 애초에 다른 기술을 고를 수
        // 없게 막으므로 턴이 날아가는 일이 없다 — 화면에서도 막고(UI),
        // 그래도 다른 인덱스가 들어오면(구버전 상대 등) 여기서 바로잡는다.
        var moveIndex = moveIndex

        // 앙코르 — 지정된 기술만 나간다. 구애와 같은 이유로 턴을 날리지 않는다.
        if atk.isEncored, let forced = atk.encoreMoveIndex,
           forced != moveIndex, atk.moves.indices.contains(forced), atk.moves[forced].usable {
            say("\(atkName)는 앙코르 때문에 \(atk.moves[forced].def.display)밖에 쓸 수 없다!")
            moveIndex = forced
        }

        if state.rules.itemEffects, let locked = atk.lockedMoveIndex, locked != moveIndex,
           atk.moves.indices.contains(locked), atk.moves[locked].usable {
            say("\(atkName)는 \(atk.heldItem?.display ?? "구애 도구") 때문에 "
                + "\(atk.moves[locked].def.display)밖에 쓸 수 없다!")
            moveIndex = locked
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

        // 프레셔 — 상대가 PP 를 두 배로 소모한다
        var ppCost = 1
        if state.rules.abilities, case .pressure = state.side(defender).active.abilityKind {
            ppCost = 2
        }
        atk.moves[moveIndex].ppLeft = max(0, atk.moves[moveIndex].ppLeft - ppCost)
        var baseMove = atk.moves[moveIndex].def
        /// 손가락흔들기로 불려나온 기술이면 원래 기술 이름
        var calledByMetronome: String?
        state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = atk

        // 손가락흔들기 — 무작위 기술을 부른다.
        // PokeAPI 는 "무작위 기술" 이라는 효과를 구조화해 주지 않으므로 직접 구현한다.
        if baseMove.name == "metronome" {
            guard let picked = metronomePool.randomElement(using: &rng) else {
                say("\(atkName)의 \(baseMove.display)! …하지만 아무 기술도 나오지 않았다!")
                return
            }
            say("\(atkName)의 \(baseMove.display)!")
            calledByMetronome = baseMove.display
            baseMove = picked
        }

        // Z기술 / 맥스기술 변환. 위력은 PokeAPI 가 주지 않으므로 원작 변환표를 쓴다.
        let move = transformed(baseMove, attacker: attacker)
        if move.name != baseMove.name {
            say("\(atkName)의 \(baseMove.display) → \(move.display)!")
        } else if calledByMetronome != nil {
            // 손가락흔들기 대전에서는 **무슨 기술이 나왔는지** 가 전부다.
            // 이름은 원작과 같은 형태로 두고, 모르는 기술이므로 타입·위력을
            // 다음 줄에 붙여준다.
            say("\(atkName)의 \(move.display)!")
            say("(\(move.type.ko) · 위력 \(move.power.map(String.init) ?? "-"))")
        } else {
            say("\(atkName)의 \(move.display)!")
        }

        // 직전 기술 기록 (아무것도않기 판정용) + 연속 사용 횟수
        do {
            var a2 = state.side(attacker).active
            a2.lastMoveIndex = moveIndex
            if a2.consecutiveMoveIndex == moveIndex {
                a2.consecutiveCount = min(4, a2.consecutiveCount + 1)
            } else {
                a2.consecutiveMoveIndex = moveIndex
                a2.consecutiveCount = 0
            }
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a2
        }

        // 모으는 턴 — 솔라빔·공중날기 등은 이번 턴에 나가지 않는다
        if move.isCharge, !skipCharge {
            var a2 = state.side(attacker).active
            a2.chargingMoveIndex = moveIndex
            a2.chargeHidden = move.chargeHides
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a2
            say(chargeMessage(move, who: atkName))
            return
        }

        // 파괴광선 계열 — 다음 턴에 움직일 수 없다.
        // 빗맞아도 반동은 온다 (2세대 이후 규칙).
        if move.mustRecharge {
            var a2 = state.side(attacker).active
            a2.mustRechargeTurns = 1
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a2
        }

        // 데이터에 구조화돼 있지 않아 손으로 구현한 기술들
        if handleScriptedMove(move, attacker: attacker, defender: defender) { return }

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

        // 축축함 — 자폭 기술을 막는다
        if state.rules.abilities, move.selfKO,
           case .damp = state.side(defender).active.abilityKind {
            say("\(state.side(defender).active.name)의 축축함! \(atkName)는 기술을 쓸 수 없다!")
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
            // 대폭발 계열은 빗나가도 쓴 쪽이 쓰러진다 (자폭이 판정보다 먼저이므로).
            // 목숨걸기 계열은 맞아야 쓰러지므로 여기서는 아무 일도 없다.
            if move.selfKO, move.selfKOBeforeMove { applySelfKO(attacker) }
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

        // 대폭발 계열(Showdown selfdestruct="always") 만 공격 판정보다 **먼저** 쓰러진다.
        // 5세대 이후 원작 규칙이고, 동시 전멸 시 승패도 이 순서로 정해진다.
        // 목숨걸기·메멘토(="ifHit") 는 효과를 낸 뒤에 쓰러져야 한다 —
        // 먼저 쓰러지면 "자기 HP 만큼" 이 0 이 되어버린다.
        if move.selfKO, move.selfKOBeforeMove { applySelfKO(attacker) }

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
                // 무효 타입이어도 대폭발 계열은 쓴 쪽이 쓰러진다
                if move.selfKO, move.selfKOBeforeMove { applySelfKO(attacker) }
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
            var delta = totalDealt * move.drainPercent / 100
            // 해감액 — 흡수하려 하면 오히려 같은 양의 피해를 받는다
            if state.rules.abilities, delta > 0,
               case .liquidOoze = state.side(defender).active.abilityKind {
                say("\(KO.t(a.name)) 해감액을 흡수해 피해를 입었다!")
                delta = -delta
            }
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

        // 타입 방어 열매를 실제로 소비한다
        if pendingResistBerry {
            var d0 = state.side(defender).active
            if let it = d0.heldItem, it.isBerry, !d0.itemConsumed {
                d0.itemConsumed = true
                state.sides[defender.rawValue].team[state.side(defender).activeIndex] = d0
                say("\(d0.name)는 \(it.display)로 피해를 줄였다!")
            }
            pendingResistBerry = false
        }

        // 피해를 입은 뒤 조건이 맞으면 열매를 먹는다
        tryEatBerry(defender)
        tryEatBerry(attacker)

        let defenderFaintedNow = state.side(defender).active.isFainted
        checkFaint(defender)

        // 자기과신 — 쓰러뜨리면 능력치가 오른다
        if state.rules.abilities, defenderFaintedNow,
           case .boostOnKO(let stat, let n) = state.side(attacker).active.abilityKind {
            var a = state.side(attacker).active
            let cur = a.stages[stat] ?? 0
            if cur < 6, !a.isFainted {
                a.stages[stat] = min(6, cur + n)
                state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a
                say("\(a.name)의 \(a.ability?.display ?? "특성")! \(KO.s(stat.ko)) 올라갔다!")
            }
        }

        // 유폭 — 쓰러질 때 접촉한 상대에게 피해
        if state.rules.abilities, defenderFaintedNow, MoveFlags.isContact(move.name),
           case .aftermath(let denom) = state.side(defender).active.abilityKind {
            var a = state.side(attacker).active
            if !a.isFainted, !isMagicGuard(a) {
                a.currentHP = max(0, a.currentHP - max(1, a.maxHP / denom))
                state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a
                say("\(KO.t(a.name)) 유폭에 휘말렸다!")
                checkFaint(attacker)
            }
        }

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

        // 묶기 기술 — 여러 턴 붙잡고 지속 피해를 준다 (바다회오리·회오리불꽃 등)
        if let range = move.trapTurns, totalDealt > 0 {
            let d0 = state.side(defender).active
            if !d0.isFainted, d0.trappedTurns == 0 {
                var d = d0
                d.trappedTurns = Int.random(in: range, using: &rng)
                d.trapMoveName = move.display
                state.sides[defender.rawValue].team[state.side(defender).activeIndex] = d
                say("\(d.name)는 \(move.display)에 붙잡혔다! (\(d.trappedTurns)턴)")
            }
        }

        // 유턴 계열 — 공격이 통했으면 자신이 물러난다
        if move.isPivot, !state.side(attacker).active.isFainted {
            state.pendingPivot.insert(attacker.rawValue)
        }

        // 저주받은바디 — 접촉이 아니어도 맞으면 발동한다
        if state.rules.abilities, totalDealt > 0,
           case .cursedBody = state.side(defender).active.abilityKind {
            applyContactAbility(attacker: attacker, defender: defender)
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

        // 목숨걸기·메멘토 계열 — 효과를 낸 뒤에 쓰러진다
        if move.selfKO, !move.selfKOBeforeMove { applySelfKO(attacker) }
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

        case .cursedBody(let percent):
            guard rng.chance(percent) else { return }
            var a = state.sides[attacker.rawValue].team[state.side(attacker).activeIndex]
            guard !a.isFainted, a.disabledTurns == 0, let last = a.lastMoveIndex else { return }
            a.disabledMoveIndex = last
            a.disabledTurns = 4
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = a
            if a.moves.indices.contains(last) {
                say("\(a.name)의 \(a.moves[last].def.display)이(가) 봉인됐다!")
            }

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

    // MARK: 나무열매
    //
    // 원작처럼 조건이 맞으면 스스로 먹고 사라진다.
    // 먹보는 발동 기준을 1/2 로 앞당기고, 긴장감은 상대가 먹지 못하게 막는다.

    /// 상대에게 긴장감이 있으면 열매를 먹을 수 없다
    private func berryBlocked(for side: BattleSide) -> Bool {
        guard state.rules.abilities else { return false }
        let foe = state.side(side.other).active
        return foe.ability?.name == "unnerve" && !foe.isFainted
    }

    /// HP 기준 열매의 발동선. 먹보면 1/4 대신 1/2 에서 먹는다.
    private func berryThreshold(_ b: Battler, defaultHalf: Bool) -> Double {
        let gluttony = state.rules.abilities && b.ability?.name == "gluttony"
        if defaultHalf { return 0.5 }
        return gluttony ? 0.5 : 0.25
    }

    /// 조건이 맞으면 열매를 먹는다. 먹었으면 true.
    @discardableResult
    private mutating func tryEatBerry(_ side: BattleSide) -> Bool {
        guard state.rules.itemEffects else { return false }
        let idx = state.side(side).activeIndex
        guard state.side(side).team.indices.contains(idx) else { return false }
        var b = state.sides[side.rawValue].team[idx]
        guard let item = b.heldItem, item.isBerry, !b.itemConsumed, !b.isFainted else { return false }
        guard !berryBlocked(for: side) else { return false }

        let ratio = Double(b.currentHP) / Double(max(1, b.maxHP))
        var ate = false

        switch item.kind {
        case .berryHeal(let half, let fraction, let flat, let dislike):
            guard ratio <= berryThreshold(b, defaultHalf: half), b.currentHP < b.maxHP else { break }
            let amount = flat ?? max(1, b.maxHP / (fraction ?? 4))
            b.currentHP = min(b.maxHP, b.currentHP + amount)
            say("\(KO.t(b.name)) \(item.display)로 체력을 회복했다!")
            // 취향에 안 맞는 열매는 혼란을 부른다 (원작 무화열매 계열)
            if dislike, b.confusionTurns == 0, rng.chance(50) {
                b.confusionTurns = Int.random(in: 2...5, using: &rng)
                say("\(KO.t(b.name)) 맛이 입에 맞지 않아 혼란에 빠졌다!")
            }
            ate = true

        case .berryCure(let target):
            if let target {
                if target == .confusion, b.confusionTurns > 0 {
                    b.confusionTurns = 0
                    say("\(KO.t(b.name)) \(item.display)로 혼란이 나았다!")
                    ate = true
                } else if b.status == target {
                    b.status = .none; b.sleepTurns = 0; b.toxicCounter = 0
                    say("\(KO.t(b.name)) \(item.display)로 \(target.ko) 상태가 나았다!")
                    ate = true
                }
            } else if b.status != .none || b.confusionTurns > 0 {
                b.status = .none; b.sleepTurns = 0; b.toxicCounter = 0; b.confusionTurns = 0
                say("\(KO.t(b.name)) \(item.display)로 상태이상이 나았다!")
                ate = true
            }

        case .berryPinchBoost(let stat):
            guard ratio <= berryThreshold(b, defaultHalf: false) else { break }
            let cur = b.stages[stat] ?? 0
            guard cur < 6 else { break }
            b.stages[stat] = min(6, cur + 1)
            say("\(KO.t(b.name)) \(item.display)로 \(KO.s(stat.ko)) 올라갔다!")
            ate = true

        case .berryRestorePP(let amount):
            guard let i = b.moves.firstIndex(where: { $0.ppLeft == 0 }) else { break }
            b.moves[i].ppLeft = min(b.moves[i].def.pp, amount)
            say("\(KO.t(b.name)) \(item.display)로 \(b.moves[i].def.display)의 PP를 회복했다!")
            ate = true

        case .berryTypeResist:
            break   // 피해 계산 시점에 소비된다

        default:
            break
        }

        if ate { b.itemConsumed = true }
        state.sides[side.rawValue].team[idx] = b
        return ate
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

    /// 발버둥 — 쓸 수 있는 기술이 없을 때 강제로 쓴다.
    /// 위력 50, 타입 상성을 받지 않으며, 준 피해의 절반(최대HP 1/4) 을 자신도 받는다.
    private mutating func performStruggle(attacker: BattleSide, defender: BattleSide) {
        let a = state.side(attacker).active
        let d = state.side(defender).active
        say("\(a.name)는 쓸 수 있는 기술이 없다! 발버둥!")

        // 타입 상성·특성 면역을 무시하는 물리 50
        let physical = true
        let A = Double(a.effective(.attack))
        let D = Double(d.effective(.defense))
        var dmg = floor(floor(floor(2.0 * Double(a.level) / 5.0 + 2.0) * 50.0 * A / D) / 50.0) + 2.0
        let rand = Double(Int.random(in: 85...100, using: &rng)) / 100.0
        dmg = floor(dmg * rand)
        _ = physical

        let dealt = applyDamage(max(1, Int(dmg)), to: defender)
        checkFaint(defender)

        // 반동 — 최대 HP 의 1/4 (매직가드도 막지 못한다)
        var me = state.side(attacker).active
        if !me.isFainted {
            me.currentHP = max(0, me.currentHP - max(1, me.maxHP / 4))
            state.sides[attacker.rawValue].team[state.side(attacker).activeIndex] = me
            say("\(KO.t(me.name)) 발버둥의 반동을 받았다!")
            checkFaint(attacker)
        }
        _ = dealt
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
            if state.rules.abilities {
                if case .flinchImmunity = b.abilityKind { return nil }
                // 불굴의마음 — 풀죽으면 오히려 스피드가 오른다
                if case .boostOnFlinch(let stat, let n) = b.abilityKind {
                    let cur = b.stages[stat] ?? 0
                    if cur < 6 { b.stages[stat] = min(6, cur + n) }
                }
            }
            return "\(KO.t(b.name)) 풀이 죽어 움직일 수 없다!"
        }
        guard state.rules.statusEffects else { return nil }

        switch b.status {
        case .sleep:
            if b.sleepTurns > 0 {
                // 일찍기상 — 잠듦이 두 배로 빨리 풀린다
                var dec = 1
                if state.rules.abilities, case .earlyBird = b.abilityKind { dec = 2 }
                b.sleepTurns = max(0, b.sleepTurns - dec)
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
        // 땅속·공중·물속에 숨어 있으면 맞지 않는다.
        // (원작에는 땅속을 맞히는 지진처럼 예외가 있지만 여기서는 단순화한다)
        if defender.chargeHidden { return false }
        // 전자부유 중에는 땅 기술이 맞지 않는다 (부유 특성과 같은 취급)
        if defender.magnetRiseTurns > 0, move.type == .ground,
           move.damageClass != .status { return false }
        // 노가드 — 양쪽 중 하나라도 있으면 반드시 명중
        if state.rules.abilities {
            if case .noGuard = attacker.abilityKind { return true }
            if case .noGuard = defender.abilityKind { return true }
        }
        guard let acc = move.accuracy else { return true }   // nil = 필중
        let mod = Battler.accEvaMultiplier(attacker.accuracyStage)
                / Battler.accEvaMultiplier(defender.evasionStage)
        var accMult = 1.0
        if state.rules.abilities {
            if case .accuracyMultiplier(let m) = attacker.abilityKind { accMult *= m }
            if case .hustle = attacker.abilityKind, move.damageClass == .physical { accMult *= 0.8 }
        }
        var final = Int((Double(acc) * mod * accMult).rounded())
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

    /// 이번 계산에서 타입 방어 열매가 쓰였는지 (계산 함수가 상태를 바꾸지 않게 분리)
    private var pendingResistBerry = false

    /// 긴장감 판정 (계산 중에는 side 를 모르므로 특성으로만 본다)
    private func berryBlockedStatic(defender: Battler, attacker: Battler) -> Bool {
        state.rules.abilities && attacker.ability?.name == "unnerve"
    }

    private mutating func computeDamage(move: MoveDef, attacker: BattleSide, defender: BattleSide) -> DamageResult {
        let a = state.side(attacker).active
        let d = state.side(defender).active
        let physical = move.damageClass == .physical

        // 무게 기반 위력 — PokeAPI 가 이 네 기술의 위력을 주지 않으므로(power=null)
        // 원작 표로 채운다. **위력이 아직 비어 있을 때만** 들어가야 재귀에 빠지지 않는다.
        if (move.power ?? 0) == 0,
           let wp = Self.weightBasedPower(move: move.name,
                                          attackerWeight: a.effectiveWeight,
                                          targetWeight: d.effectiveWeight) {
            var m2 = move
            m2.power = wp
            m2.specialDamage = .none
            return computeDamage(move: m2, attacker: attacker, defender: defender)
        }

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

        var power = move.power ?? 0

        // 연속으로 쓰면 세지는 기술 — 데이터에 없어 직접 처리한다.
        // 연속자르기·데구르르는 두 배씩, 에코보이스·울음소리는 더해진다.
        switch move.name {
        case "fury-cutter", "rollout", "ice-ball":
            // 1턴 40 → 80 → 160 → 320 (상한)
            power = min(power * (1 << min(3, a.consecutiveCount)), power * 8)
        case "echoed-voice":
            // 40 → 80 → 120 → 160 → 200 (상한)
            power = min(power * (1 + min(4, a.consecutiveCount)), power * 5)
        case "spit-up":
            // 비축한 만큼 (100 / 200 / 300). 비축이 없으면 실패한다.
            power = 100 * max(0, a.stockpile)
        default: break
        }

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
        // 초식·전기엔진·번개유도 — 무효화하고 능력이 오른다
        if state.rules.abilities, case .absorbAndBoost(let t, _, _) = foeAbility, move.type == t {
            typeMult = 0
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
            // 불가사의부적 — 효과가 굉장한 기술만 통한다
            if case .wonderGuard = foeAbility, typeMult < 2 { typeMult = 0 }
            // 메가런처·칼날몸 — 특정 기술군 강화
            if case .moveTypeBoost(let names, let m) = a.abilityKind,
               names.contains(move.name) { extra *= m }
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

        // 타입 방어 열매 — 효과가 굉장한 기술을 반감시킨다 (여기서 소비 표시만 하고
        // 실제 소비는 applyDamage 뒤 consumeResistBerry 에서 한다)
        var berryHalved = false
        if state.rules.itemEffects, typeMult >= 2,
           case .berryTypeResist(let bt) = d.itemKind, bt == move.type,
           !berryBlockedStatic(defender: d, attacker: a) {
            extra *= 0.5
            berryHalved = true
        }
        pendingResistBerry = berryHalved

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
            if case .statMultiplier(let s, let x) = b.abilityKind, s == stat { m *= x }
            // 의욕 — 공격 1.5배 (명중은 accuracyCheck 에서 깎는다)
            if case .hustle = b.abilityKind, stat == .attack { m *= 1.5 }
            // 무기력 — HP 절반 이하면 공격·특공 반감
            if case .defeatist = b.abilityKind, b.currentHP * 2 <= b.maxHP,
               stat == .attack || stat == .spAttack { m *= 0.5 }
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

    /// 무게로 위력이 정해지는 기술 (원작 표).
    /// 저울짓기·풀묶기는 **상대 무게**, 헤비봄버·기관차는 **무게 비율**을 본다.
    static func weightBasedPower(move: String, attackerWeight: Int, targetWeight: Int) -> Int? {
        switch move {
        case "low-kick", "grass-knot":
            let kg = Double(targetWeight) / 10.0
            switch kg {
            case ..<10:   return 20
            case ..<25:   return 40
            case ..<50:   return 60
            case ..<100:  return 80
            case ..<200:  return 100
            default:      return 120
            }
        case "heavy-slam", "heat-crash":
            guard targetWeight > 0 else { return 120 }
            let ratio = Double(attackerWeight) / Double(targetWeight)
            switch ratio {
            case 5...:    return 120
            case 4..<5:   return 100
            case 3..<4:   return 80
            case 2..<3:   return 60
            default:      return 40
            }
        default:
            return nil
        }
    }

    /// 실제로 깎인 양을 돌려준다 (흡수 계산에 필요).
    /// 옹골참(특성) 과 기합의띠(도구) 는 풀피에서 받는 일격을 1 HP 로 버티게 한다.
    private mutating func applyDamage(_ amount: Int, to side: BattleSide) -> Int {
        var b = state.side(side).active
        var amount = amount

        // 대타출동 인형이 있으면 인형이 먼저 받는다.
        // 인형이 부서질 때 넘치는 데미지는 원작대로 **본체로 넘기지 않는다.**
        if let sub = b.substituteHP, sub > 0 {
            let absorbed = min(sub, amount)
            let left = sub - absorbed
            b.substituteHP = left > 0 ? left : nil
            state.sides[side.rawValue].team[state.side(side).activeIndex] = b
            if left > 0 {
                say("\(b.name)의 인형이 데미지를 받았다! (인형 HP \(left))")
            } else {
                say("\(b.name)의 인형이 부서졌다!")
            }
            return absorbed
        }

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

        if move.isPivot, !state.side(attacker).active.isFainted {
            state.pendingPivot.insert(attacker.rawValue)
            acted = true
        }

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
            // 리프가드 — 특정 날씨에서는 상태이상에 걸리지 않는다
            if state.rules.abilities, state.rules.weather, state.field.hasWeather,
               case .noStatusInWeather(let w) = t.abilityKind, w == state.field.weather {
                say("\(t.name)는 \(t.ability?.display ?? "특성") 때문에 상태이상이 되지 않는다!")
                return false
            }
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

            // 싱크로 — 받은 상태이상을 건 쪽에게도 돌려준다
            if state.rules.abilities, case .synchronize = t.abilityKind,
               target != attacker,
               move.ailment == .burn || move.ailment == .poison
                || move.ailment == .toxic || move.ailment == .paralysis {
                let src = target.other
                let sIdx = state.side(src).activeIndex
                if state.side(src).team.indices.contains(sIdx),
                   state.sides[src.rawValue].team[sIdx].status == .none,
                   !state.sides[src.rawValue].team[sIdx].isFainted {
                    say("\(t.name)의 싱크로!")
                    state.sides[target.rawValue].team[state.side(target).activeIndex] = t
                    inflictDirect(move.ailment, on: src, source: "싱크로")
                    return true
                }
            }
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

            if state.rules.abilities {
                // 가속 — 턴마다 스피드 상승
                if case .speedBoostEachTurn = b.abilityKind {
                    let cur = b.stages[.speed] ?? 0
                    if cur < 6 {
                        b.stages[.speed] = cur + 1
                        say("\(b.name)의 가속! 스피드가 올라갔다!")
                    }
                }
                // 탈피 — 확률로 상태이상 회복
                if case .shedSkin(let p) = b.abilityKind, b.status != .none, rng.chance(p) {
                    say("\(KO.t(b.name)) 탈피로 \(b.status.ko) 상태가 나았다!")
                    b.status = .none; b.sleepTurns = 0; b.toxicCounter = 0
                }
                // 촉촉바디 — 특정 날씨에서 상태이상 회복
                if state.rules.weather, state.field.hasWeather,
                   case .healInWeather(let w) = b.abilityKind, w == state.field.weather,
                   b.status != .none {
                    say("\(KO.t(b.name)) \(b.ability?.display ?? "특성")(으)로 상태이상이 나았다!")
                    b.status = .none; b.sleepTurns = 0; b.toxicCounter = 0
                }
                // 포이즌힐 — 독 피해 대신 회복
                if case .poisonHeal = b.abilityKind,
                   b.status == .poison || b.status == .toxic {
                    if b.currentHP < b.maxHP {
                        b.currentHP = min(b.maxHP, b.currentHP + max(1, b.maxHP / 8))
                        say("\(KO.t(b.name)) 포이즌힐로 체력을 회복했다!")
                    }
                    state.sides[s.rawValue].team[state.side(s).activeIndex] = b
                    continue
                }
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

            // 저주 — 매 턴 최대 HP 의 1/4
            if b.cursed, b.currentHP > 0 {
                let d = max(1, b.maxHP / 4)
                b.currentHP = max(0, b.currentHP - d)
                say("\(KO.t(b.name)) 저주 때문에 데미지를 받았다!")
            }

            // 하품 — 턴수가 다 되면 잠든다
            if b.drowsyTurns > 0, b.currentHP > 0 {
                b.drowsyTurns -= 1
                if b.drowsyTurns == 0 {
                    if b.status == .none, state.rules.statusEffects {
                        b.status = .sleep
                        b.sleepTurns = Int.random(in: 2...4, using: &rng)
                        say("\(KO.t(b.name)) 잠들어 버렸다!")
                    }
                }
            }

            // 앙코르 — 남은 턴을 줄이고 끝나면 풀어준다
            if b.encoreTurns > 0 {
                b.encoreTurns -= 1
                if b.encoreTurns == 0 {
                    b.encoreMoveIndex = nil
                    say("\(b.name)의 앙코르가 풀렸다!")
                }
            }

            // 전자부유 — 남은 턴을 줄인다
            if b.magnetRiseTurns > 0 {
                b.magnetRiseTurns -= 1
                if b.magnetRiseTurns == 0 {
                    say("\(b.name)의 전자부유가 끝났다!")
                }
            }
            state.sides[s.rawValue].team[state.side(s).activeIndex] = b
            checkFaint(s)
        }
        // 픽업 — 상대가 소비한 도구를 주워온다
        if state.rules.abilities, state.rules.itemEffects {
            for side in [BattleSide.host, .guest] {
                let i = state.side(side).activeIndex
                guard state.side(side).team.indices.contains(i) else { continue }
                var me = state.sides[side.rawValue].team[i]
                guard case .pickup = me.abilityKind, me.heldItem == nil || me.itemConsumed,
                      !me.isFainted else { continue }
                let fIdx = state.side(side.other).activeIndex
                guard state.side(side.other).team.indices.contains(fIdx) else { continue }
                var foe = state.sides[side.other.rawValue].team[fIdx]
                guard let used = foe.heldItem, foe.itemConsumed else { continue }
                // 점착이 있으면 못 가져온다
                if case .stickyHold = foe.abilityKind { continue }
                me.heldItem = used
                me.itemConsumed = false
                foe.heldItem = nil
                state.sides[side.rawValue].team[i] = me
                state.sides[side.other.rawValue].team[fIdx] = foe
                say("\(me.name)는 픽업으로 \(used.display)을(를) 주웠다!")
            }
        }

        // 지속 피해로 HP 가 떨어졌을 수 있으니 열매를 확인한다
        tryEatBerry(.host)
        tryEatBerry(.guest)

        applyAutoForms()
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

        // 봉인 턴수 감소
        for side in [BattleSide.host, .guest] {
            let i = state.side(side).activeIndex
            guard state.side(side).team.indices.contains(i) else { continue }
            var b = state.sides[side.rawValue].team[i]
            guard b.disabledTurns > 0 else { continue }
            b.disabledTurns -= 1
            if b.disabledTurns == 0 {
                if let d = b.disabledMoveIndex, b.moves.indices.contains(d) {
                    say("\(b.name)의 \(b.moves[d].def.display) 봉인이 풀렸다!")
                }
                b.disabledMoveIndex = nil
            }
            state.sides[side.rawValue].team[i] = b
        }

        // 묶기 — 지속 피해 후 턴수 감소
        for side in [BattleSide.host, .guest] {
            let i = state.side(side).activeIndex
            guard state.side(side).team.indices.contains(i) else { continue }
            var b = state.sides[side.rawValue].team[i]
            guard b.trappedTurns > 0 else { continue }

            // 기술로 묶인 경우에만 지속 피해를 준다 (다이맥스고스트는 묶기만 한다)
            if let src = b.trapMoveName, !b.isFainted,
               !(state.rules.abilities && isMagicGuard(b)) {
                b.currentHP = max(0, b.currentHP - max(1, b.maxHP / 8))
                say("\(KO.t(b.name)) \(src)에 시달리고 있다!")
            }
            b.trappedTurns -= 1
            if b.trappedTurns == 0 {
                b.trapMoveName = nil
                say("\(KO.t(b.name)) 자유로워졌다!")
            }
            state.sides[side.rawValue].team[i] = b
            checkFaint(side)
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
        let h = state.side(.host).remaining
        let g = state.side(.guest).remaining

        // 이미 끝난 걸로 기록됐어도, 그 뒤 반동·자폭·유폭으로 승자까지 전멸할 수 있다.
        // 그런 경우 기록을 바로잡는다 (전멸한 쪽이 승자로 남으면 안 된다).
        if case .finished(let w) = state.phase {
            guard let w else { return }
            let winnerRemaining = state.sides[w].remaining
            guard winnerRemaining == 0 else { return }
            if h == 0 && g == 0 {
                say("[정정] 양쪽 모두 쓰러졌다 — 무승부!")
                state.phase = .finished(winner: nil)
            } else {
                let other = w == 0 ? 1 : 0
                say("[정정] \(state.sides[other].playerName) 승리!")
                state.phase = .finished(winner: other)
            }
            return
        }

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

// MARK: - 데이터에 없어서 손으로 구현한 기술
//
// PokéAPI 는 이 효과들을 아예 주지 않고 (잠자기는 ailment=none, healing=0),
// Showdown 도 코드로만 표현한다. 그래서 여기서 직접 처리한다.
// `handleScriptedMove` 가 true 를 돌려주면 그 기술은 여기서 끝난다.
extension BattleEngine {

    /// 모으는 턴에 나오는 문구. 원작처럼 기술마다 다르다.
    func chargeMessage(_ move: MoveDef, who: String) -> String {
        switch move.name {
        case "fly", "bounce":     return "\(who)는 하늘 높이 날아올랐다!"
        case "dig":               return "\(who)는 땅속으로 파고들었다!"
        case "dive":              return "\(who)는 물속으로 들어갔다!"
        case "phantom-force", "shadow-force":
                                  return "\(who)는 모습을 감췄다!"
        case "solar-beam", "solar-blade":
                                  return "\(who)는 빛을 흡수했다!"
        case "sky-attack":        return "\(who)의 몸이 빛나기 시작했다!"
        case "meteor-beam":       return "\(who)는 우주의 힘을 모으고 있다!"
        default:                  return "\(who)는 힘을 모으고 있다!"
        }
    }

    mutating func handleScriptedMove(_ move: MoveDef, attacker: BattleSide,
                                     defender: BattleSide) -> Bool {
        var a = state.side(attacker).active
        var d = state.side(defender).active
        let aName = a.name

        switch move.name {

        // 잠자기 — HP 를 모두 채우고 **자신이** 2턴 잠든다.
        // PokéAPI 는 ailment=none, healing=0 으로 줘서 아무 일도 일어나지 않았다.
        case "rest":
            guard state.rules.statusEffects else {
                say("\(aName)의 잠자기! …하지만 상태이상이 꺼져 있다!")
                return true
            }
            if a.currentHP >= a.maxHP {
                say("\(aName)의 잠자기! …하지만 실패했다!")
                return true
            }
            // 불면·의기양양처럼 잠들지 못하는 특성이면 실패한다
            if state.rules.abilities, case .statusImmunity(let imm) = a.abilityKind, imm == .sleep {
                say("\(aName)는 \(a.ability?.display ?? "특성") 때문에 잠들 수 없다!")
                return true
            }
            let healed = a.maxHP - a.currentHP
            a.currentHP = a.maxHP
            a.status = .sleep
            a.sleepTurns = 2
            commit(a, attacker)
            say("\(KO.t(aName)) 잠들어 체력을 회복했다! (+\(healed))")
            return true

        // 저주 — 고스트 타입이면 최대 HP 의 절반을 잃고 상대를 저주한다.
        // 아니면 공격·방어가 오르고 스피드가 떨어진다.
        case "curse":
            if a.types.contains(.ghost) {
                guard !d.cursed else {
                    say("\(aName)의 저주! …하지만 실패했다!")
                    return true
                }
                let cost = max(1, a.maxHP / 2)
                a.currentHP = max(0, a.currentHP - cost)
                d.cursed = true
                commit(a, attacker); commit(d, defender)
                say("\(aName)는 자신의 체력을 깎아 \(d.name)를 저주했다!")
                if a.currentHP <= 0 { say("\(KO.t(aName)) 쓰러졌다!") }
                return true
            } else {
                bump(&a, .attack, +1); bump(&a, .defense, +1); bump(&a, .speed, -1)
                commit(a, attacker)
                say("\(aName)의 저주! 공격·방어가 올라가고 스피드가 떨어졌다!")
                return true
            }

        // 배북 — 최대 HP 의 절반을 깎고 공격을 **최대까지** 올린다
        case "belly-drum":
            let cost = max(1, a.maxHP / 2)
            if a.currentHP <= cost || (a.stages[.attack] ?? 0) >= 6 {
                say("\(aName)의 배북! …하지만 실패했다!")
                return true
            }
            a.currentHP -= cost
            a.stages[.attack] = 6
            commit(a, attacker)
            say("\(aName)는 체력을 깎아 공격을 최대까지 올렸다!")
            return true

        // 대타출동 — 최대 HP 의 1/4 을 써서 인형을 세운다.
        // 인형이 있는 동안 데미지와 상태이상을 대신 받는다.
        case "substitute":
            if a.hasSubstitute {
                say("\(aName)의 대타출동! …하지만 이미 인형이 있다!")
                return true
            }
            let cost = max(1, a.maxHP / 4)
            if a.currentHP <= cost {
                say("\(aName)의 대타출동! …하지만 체력이 부족했다!")
                return true
            }
            a.currentHP -= cost
            a.substituteHP = cost
            commit(a, attacker)
            say("\(aName)는 인형을 세웠다! (인형 HP \(cost))")
            return true

        // 아픔나누기 — 양쪽 HP 를 합쳐 반씩 나눈다
        case "pain-split":
            let total = a.currentHP + d.currentHP
            let each = total / 2
            a.currentHP = min(a.maxHP, each)
            d.currentHP = min(d.maxHP, each)
            commit(a, attacker); commit(d, defender)
            say("\(aName)는 아픔을 나눴다! (양쪽 \(each))")
            return true

        // 텍스처 — 자신의 타입을 **가진 기술 중 하나**의 타입으로 바꾼다
        case "conversion":
            guard let first = a.moves.first?.def.type else { return true }
            a.types = [first]
            commit(a, attacker)
            say("\(aName)는 \(first.ko) 타입이 되었다!")
            return true

        // 텍스처2 — 상대가 마지막에 쓴 기술에 강한 타입이 된다.
        // 마지막 기술을 모르면 실패한다.
        case "conversion2":
            guard let li = d.lastMoveIndex, d.moves.indices.contains(li) else {
                say("\(aName)의 텍스처2! …하지만 실패했다!")
                return true
            }
            let incoming = d.moves[li].def.type
            let resist = PType.allCases.first { t in
                chart.multiplier(attack: incoming, defenders: [t]) < 1
            }
            guard let resist else {
                say("\(aName)의 텍스처2! …하지만 실패했다!")
                return true
            }
            a.types = [resist]
            commit(a, attacker)
            say("\(aName)는 \(resist.ko) 타입이 되었다!")
            return true

        // 물놀이(Soak) — 상대를 물 타입으로 만든다
        case "soak":
            if d.types == [.water] {
                say("\(aName)의 물놀이! …하지만 실패했다!")
                return true
            }
            d.types = [.water]
            commit(d, defender)
            say("\(d.name)는 물 타입이 되었다!")
            return true

        // 할로윈 / 숲의저주 — 상대에게 타입을 **추가**한다
        case "trick-or-treat", "forests-curse":
            let add: PType = move.name == "trick-or-treat" ? .ghost : .grass
            if d.types.contains(add) {
                say("\(aName)의 \(move.display)! …하지만 실패했다!")
                return true
            }
            d.types.append(add)
            commit(d, defender)
            say("\(d.name)에게 \(add.ko) 타입이 추가되었다!")
            return true

        // 앙코르 — 상대가 마지막에 쓴 기술만 3턴 동안 쓰게 만든다
        case "encore":
            guard let li = d.lastMoveIndex, d.moves.indices.contains(li),
                  d.moves[li].usable, !d.isEncored else {
                say("\(aName)의 앙코르! …하지만 실패했다!")
                return true
            }
            d.encoreTurns = 3
            d.encoreMoveIndex = li
            commit(d, defender)
            say("\(d.name)는 앙코르로 \(d.moves[li].def.display)밖에 쓸 수 없게 되었다! (3턴)")
            return true

        // 하품 — 다음 턴이 끝날 때 잠든다
        case "yawn":
            guard state.rules.statusEffects else {
                say("\(aName)의 하품! …하지만 상태이상이 꺼져 있다!")
                return true
            }
            guard d.status == .none, d.drowsyTurns == 0 else {
                say("\(aName)의 하품! …하지만 실패했다!")
                return true
            }
            d.drowsyTurns = 2       // 이번 턴 끝 + 다음 턴 끝 => 다음 턴 끝에 잠든다
            commit(d, defender)
            say("\(d.name)는 졸음이 몰려왔다!")
            return true

        // 뱉어내기 — 비축이 없으면 쓸 수 없다. 쓰면 비축을 비운다.
        // (위력은 데미지 계산에서 비축 단계로 정한다)
        case "spit-up":
            guard a.stockpile > 0 else {
                say("\(aName)의 뱉어내기! …하지만 실패했다!")
                return true
            }
            return false   // 데미지 계산은 평소 경로로 보낸다

        // 비축 — 쌓아두면 뱉어내기·통째로꿀꺽이 세진다 (최대 3)
        case "stockpile":
            guard a.stockpile < 3 else {
                say("\(aName)의 비축! …더 이상 쌓을 수 없다!")
                return true
            }
            a.stockpile += 1
            bump(&a, .defense, +1); bump(&a, .spDefense, +1)
            commit(a, attacker)
            say("\(aName)는 힘을 비축했다! (\(a.stockpile)단계)")
            return true

        // 통째로꿀꺽 — 비축한 만큼 회복하고 비축을 비운다
        case "swallow":
            guard a.stockpile > 0 else {
                say("\(aName)의 통째로꿀꺽! …하지만 실패했다!")
                return true
            }
            let fraction: Double = a.stockpile == 1 ? 0.25 : (a.stockpile == 2 ? 0.5 : 1.0)
            let heal = max(1, Int(Double(a.maxHP) * fraction))
            let before = a.currentHP
            a.currentHP = min(a.maxHP, a.currentHP + heal)
            let gained = a.currentHP - before
            a.stockpile = 0
            commit(a, attacker)
            say("\(aName)는 비축한 것을 삼켜 체력을 회복했다! (+\(gained))")
            return true

        // 전자부유 — 5턴 동안 땅 기술을 받지 않는다
        case "magnet-rise":
            guard a.magnetRiseTurns == 0 else {
                say("\(aName)의 전자부유! …하지만 실패했다!")
                return true
            }
            // 쓴 턴의 종료 처리에서 한 번 깎이므로 6 을 준다 → 이후 5턴 유효
            a.magnetRiseTurns = 6
            commit(a, attacker)
            say("\(aName)는 전자기의 힘으로 떠올랐다! (5턴)")
            return true

        // 검은눈빛 / 블랙아이즈 — 도망갈 수 없게 만든다
        case "mean-look", "block", "spider-web":
            guard !d.cannotFlee else {
                say("\(aName)의 \(move.display)! …하지만 실패했다!")
                return true
            }
            d.cannotFlee = true
            commit(d, defender)
            say("\(d.name)는 도망갈 수 없게 되었다!")
            return true

        // 미러타입 — 상대와 같은 타입이 된다
        case "reflect-type":
            a.types = d.types
            commit(a, attacker)
            say("\(aName)는 \(d.name)와 같은 타입이 되었다!")
            return true

        default:
            return false
        }
    }

    private mutating func commit(_ b: Battler, _ side: BattleSide) {
        state.sides[side.rawValue].team[state.side(side).activeIndex] = b
    }

    private func bump(_ b: inout Battler, _ stat: Stat, _ n: Int) {
        let cur = b.stages[stat] ?? 0
        b.stages[stat] = max(-6, min(6, cur + n))
    }
}
