import Foundation

/// 배틀에 참가하는 한 마리. 개체값 31 / 노력치 0 고정 — 데이터가 없으므로 전원 동일 조건.
/// 레벨도 방 설정으로 통일한다. 즉 **차이를 만드는 건 종족값·타입·성격·기술 4개뿐**이다.
struct Battler: Codable, Identifiable, Sendable, Equatable {
    var id: String                  // RosterSlot.id
    var speciesID: Int
    var name: String                // 표시용 (한글명)
    var types: [PType]
    var level: Int
    var natureName: String
    var isShiny: Bool
    var fullyEvolved: Bool

    var maxHP: Int
    var currentHP: Int
    var stats: [Stat: Int]          // hp 제외 실효 스탯
    var moves: [MoveSlot]

    /// 지닌 도구. 메가진화·Z기술·다이맥스는 해당 도구가 없으면 쓸 수 없다.
    var heldItem: ItemDef?

    // MARK: 2턴 기술 / 반동 / 특수 상태
    //
    // PokéAPI 도 Showdown 도 이런 효과를 **구조화해 주지 않는다** (Showdown 은
    // 코드로 쓴다). 그래서 상태를 직접 들고 처리한다.

    /// 모으는 중인 기술의 인덱스 (솔라빔·공중날기 등). nil 이면 모으는 중이 아니다.
    var chargingMoveIndex: Int?
    /// 모으는 동안 몸을 숨겼는가 (땅속·공중·물속) — 대부분의 기술이 맞지 않는다
    var chargeHidden: Bool = false
    /// 파괴광선을 쓴 뒤 못 움직이는 턴이 남았는가
    var mustRechargeTurns: Int = 0
    /// 대타출동 인형의 남은 HP. nil 이면 인형이 없다.
    var substituteHP: Int?
    /// 저주 — 매 턴 최대 HP 의 1/4 을 잃는다
    var cursed: Bool = false

    // MARK: 앙코르 · 하품 · 비축 · 누적 위력
    //
    // 전부 데이터에 구조화돼 있지 않아 상태를 직접 들고 처리한다.

    /// 앙코르 — 이 기술만 쓰게 되는 남은 턴수
    var encoreTurns: Int = 0
    var encoreMoveIndex: Int?
    /// 하품 — 이 턴수가 0 이 되면 잠든다
    var drowsyTurns: Int = 0
    /// 비축 횟수 (뱉어내기·통째로꿀꺽의 위력·회복량을 정한다). 최대 3.
    var stockpile: Int = 0
    /// 같은 기술을 연속으로 쓴 횟수 (연속자르기·데구르르·에코보이스가 세진다)
    var consecutiveMoveIndex: Int?
    var consecutiveCount: Int = 0
    /// 전자부유 — 땅 기술을 받지 않는 남은 턴수
    var magnetRiseTurns: Int = 0
    /// 검은눈빛 등으로 도망갈 수 없는 상태 (교체 불가)
    var cannotFlee: Bool = false
    /// 원시회귀 상태인가 (등장할 때 자동으로 바뀐다)
    var isPrimal: Bool = false

    // MARK: 난동부리기 · 미래예지 · 도발 · 기충전 · 길동무

    /// 난동부리기 — 같은 기술이 강제로 나가는 남은 턴수. 끝나면 혼란에 빠진다.
    var rampageTurns: Int = 0
    var rampageMoveIndex: Int?
    /// 도발 — 변화기를 쓸 수 없는 남은 턴수
    var tauntTurns: Int = 0
    /// 기충전 — 급소 랭크 (원작 +2)
    var focusEnergy: Bool = false
    /// 길동무 — 이번 턴에 쓰러지면 쓰러뜨린 쪽도 함께 쓰러진다
    var destinyBond: Bool = false

    // MARK: 남은 지속 상태

    /// 버티기 — 이번 턴에 쓰러지지 않고 HP 1 로 버틴다
    var enduring: Bool = false
    /// 봉인 — 상대가 가진 기술을 쓸 수 없다 (내가 가진 기술과 같은 것)
    var sealedMoves: Set<String> = []
    /// 아쿠아링 — 매 턴 최대 HP 의 1/16 회복
    var aquaRing: Bool = false
    /// 웅크리기 — 자신을 축소해 명중률이 떨어진다 (회피 랭크로 처리)
    var minimized: Bool = false
    /// 위액 — 특성이 사라진다
    var abilitySuppressed: Bool = false
    /// 충전 — 다음 전기 기술의 위력이 2배
    var charged: Bool = false
    /// 트집 — 이미 있는 tormented 를 쓴다
    /// 파워트릭 — 공격과 방어가 뒤바뀐다
    var powerTricked: Bool = false
    /// 헤롱헤롱(매혹) — 확률로 움직이지 못한다
    var infatuated: Bool = false
    /// 웅크리기 — 데구르르·아이스볼의 위력이 두 배가 된다 (숨은 효과)
    var defenseCurled: Bool = false
    /// 떨어뜨리기 — 땅으로 끌어내려져 땅 기술을 피할 수 없다
    /// (비행 타입·부유 특성·전자부유가 모두 무시된다)
    var grounded: Bool = false

    var isRampaging: Bool { rampageTurns > 0 && rampageMoveIndex != nil }

    var isCharging: Bool { chargingMoveIndex != nil }
    var isEncored: Bool { encoreTurns > 0 && encoreMoveIndex != nil }

    /// 모으는 중인 기술 이름 (연출에서 어디로 숨었는지 정하는 데 쓴다)
    var chargingMoveName: String? {
        guard let i = chargingMoveIndex, moves.indices.contains(i) else { return nil }
        return moves[i].def.name
    }

    /// 숨어 있는 동안 화면에 띄울 안내
    var hiddenNote: String? {
        guard chargeHidden else { return nil }
        switch chargingMoveName {
        case "fly", "bounce":  return "공중으로 피했다"
        case "sky-attack":     return "높이 날아올랐다"
        case "dig":            return "땅속에 숨었다"
        case "dive":           return "물속에 숨었다"
        default:               return "모습을 감췄다"
        }
    }
    var hasSubstitute: Bool { (substituteHP ?? 0) > 0 }
    /// 특성
    var ability: AbilityDef?
    /// 도구가 소비됐는가 (기합의띠 등 1회성)
    var itemConsumed: Bool = false
    /// 구애 계열로 고정된 기술 (처음 쓴 기술만 계속 쓸 수 있다)
    var lockedMoveIndex: Int?
    /// 등장 시 특성(위협 등)을 이미 발동했는가
    var entryAbilityFired: Bool = false

    /// 조임 — 교체할 수 없다 (교체룰이 들어오면 작동한다)
    var trappedTurns: Int = 0
    /// 묶기 기술로 붙잡혔을 때 그 기술 이름 (지속 피해 로그용).
    /// nil 이면 다이맥스고스트처럼 피해 없이 묶기만 하는 경우다.
    var trapMoveName: String?
    /// 아무것도않기 — 같은 기술을 연속으로 쓸 수 없다
    var tormented: Bool = false
    /// 저주받은바디로 봉인된 기술과 남은 턴
    var disabledMoveIndex: Int?
    var disabledTurns: Int = 0
    /// 무게 (헥토그램). 헤비메탈·저울짓기 계산에 쓴다.
    var weight: Int = 0
    /// 직전에 쓴 기술 (아무것도않기 판정용)
    var lastMoveIndex: Int?
    /// 이번 턴 방어 상태인가
    var isProtecting: Bool = false
    /// 방어를 연속으로 쓴 횟수 (연속 사용 시 성공률이 떨어진다)
    var protectStreak: Int = 0

    var isTrapped: Bool { trappedTurns > 0 }

    // 전투 중 상태
    var status: Ailment = .none
    var sleepTurns: Int = 0
    var toxicCounter: Int = 0
    var stages: [Stat: Int] = [:]   // ±6
    var accuracyStage: Int = 0
    var evasionStage: Int = 0
    var confusionTurns: Int = 0
    var mustFlinch: Bool = false

    // 특수 변신 자격 / 상태
    /// 이 개체가 쓸 수 있는 메가 폼 이름들 (없으면 메가진화 불가)
    var megaForms: [String] = []
    /// 거다이맥스 폼 이름 (없으면 거다이맥스 불가)
    var gmaxForm: String?
    /// 이미 메가진화했는가
    var isMega: Bool = false
    /// 다이맥스/거다이맥스 남은 턴수 (0 이면 평상시)
    var dynamaxTurnsLeft: Int = 0
    /// 거다이맥스로 발동했는가 (일반 다이맥스와 표시·전용기가 다르다)
    var isGigantamaxed: Bool = false
    /// 거다이맥스 전용기 (종별로 정해져 있다). PokeAPI 에 없어 표로 관리한다.
    var gmaxMove: GMaxMove?
    /// 급소율 단계 (다이맥스태클 등으로 오른다)
    var critStage: Int = 0
    /// 변신 표시용 라벨 ("메가 X", "다이맥스", "거다이맥스")
    var formLabel: String?
    /// 전투 전에 고른 폼 (로토무 히트 등). 배틀 시작 시 이미 적용돼 있다.
    var chosenForm: String?
    /// 배틀 중 자동 변신으로 바뀐 현재 폼 (캐스퐁·불비달마)
    var autoForm: String?
    /// 메가진화·거다이맥스로 바뀐 폼 이름 (스프라이트 교체용)
    var visualForm: String?

    /// 지금 화면에 그려야 할 스프라이트의 폼 이름.
    /// 자동 변신 > 메가·거다이맥스 > 전투 전 선택 순으로 우선한다.
    var spriteForm: String? { autoForm ?? visualForm ?? chosenForm }
    /// 다이맥스는 전용 스프라이트가 없으므로 크기로 표현한다
    var spriteScale: CGFloat { isDynamaxed ? 1.35 : 1.0 }
    /// 자동 변신 전 원래 종족값 — 되돌릴 때 쓴다
    var baseStatsSnapshot: [Stat: Int] = [:]
    var baseTypesSnapshot: [PType] = []
    /// 다이맥스 해제 시 되돌릴 원래 HP 상한
    var baseMaxHP: Int = 0

    /// 다이맥스 또는 거다이맥스 상태 — 둘 다 기술이 맥스 기술로 바뀐다
    var isDynamaxed: Bool { dynamaxTurnsLeft > 0 }

    /// 특성 보정이 반영된 실효 무게 (헤비메탈·라이트메탈)
    var effectiveWeight: Int {
        if case .weightMultiplier(let m) = abilityKind {
            return max(1, Int(Double(weight) * m))
        }
        return weight
    }

    /// 지닌 도구의 효과 (소비됐으면 없음)
    var itemKind: ItemKind {
        guard let heldItem, !itemConsumed else { return .none }
        return heldItem.kind
    }
    /// 배틀에 반영되는 특성.
    ///
    /// 위액을 맞으면 특성이 사라진다 — 여기서 한 번에 막아야 모든 계산이
    /// 일관되게 특성 없음으로 돈다.
    var abilityKind: AbilityKind {
        abilitySuppressed ? .none : (ability?.kind ?? .none)
    }

    /// 이 개체가 메가진화할 수 있는 폼 (도구가 허용하는 것만)
    var megaFormFromItem: String? {
        if case .megaStone(let f) = itemKind, megaForms.contains(f) { return f }
        return nil
    }
    /// Z기술을 쓸 수 있는 타입 (도구 기준)
    var zCrystalType: PType? {
        if case .zCrystalType(let t) = itemKind { return t }
        return nil
    }
    /// 전용 Z크리스탈을 지녔고 그 종이 맞는가
    var hasSignatureZ: Bool {
        if case .zCrystalSignature(let sid) = itemKind { return sid == speciesID }
        return false
    }
    var hasDynamaxBand: Bool { if case .dynamaxBand = itemKind { return true }; return false }
    var hasMaxMushroom: Bool { if case .maxMushroom = itemKind { return true }; return false }
    var canMega: Bool { !megaForms.isEmpty && !isMega }
    /// 다이맥스는 종족 제한이 없다 (원작에서도 거의 모든 포켓몬이 가능)
    var canDynamax: Bool { !isDynamaxed }
    /// 거다이맥스는 전용 폼이 있는 종만
    var canGigantamax: Bool { gmaxForm != nil && !isDynamaxed }

    /// 도구까지 고려한 자격. `requireItems` 가 켜져 있을 때 쓴다.
    func canMega(requiringItem: Bool) -> Bool {
        guard canMega else { return false }
        return requiringItem ? megaFormFromItem != nil : true
    }
    /// 다이맥스 밴드 → **일반 다이맥스만.**
    ///
    /// 원작에서 다이맥스 밴드는 트레이너의 열쇠 아이템이고 다이버섯은 거다이맥스 인자를
    /// 여는 요리 재료다 — 둘 다 원래는 지닌 도구가 아니다.
    /// 이 게임은 도구 슬롯 하나로 자격을 관리하므로 각자 역할을 하나씩 맡긴다.
    /// (예전에는 밴드가 거다이맥스까지 허용해서 다이버섯을 끼울 이유가 없었다)
    func canDynamax(requiringItem: Bool) -> Bool {
        guard canDynamax else { return false }
        return requiringItem ? hasDynamaxBand : true
    }

    /// 다이버섯 → **거다이맥스만.** 전용 폼이 있는 종에게만 의미가 있다.
    func canGigantamax(requiringItem: Bool) -> Bool {
        guard canGigantamax else { return false }
        return requiringItem ? hasMaxMushroom : true
    }
    func canZMove(requiringItem: Bool) -> Bool {
        guard canZMove else { return false }
        guard requiringItem else { return true }
        // 전용 Z크리스탈은 그 종이면 공격기만 있으면 된다
        if hasSignatureZ { return true }
        // 타입 Z크리스탈은 일치하는 공격기가 있어야 한다
        guard let t = zCrystalType else { return false }
        return moves.contains { $0.usable && $0.def.damageClass != .status
                                && $0.def.isDamaging && $0.def.type == t }
    }

    /// Z기술은 도구(Z크리스탈) 기반이라 종족 제한이 없다.
    /// 다만 물리·특수 공격기가 하나라도 있어야 변환할 대상이 생긴다.
    var canZMove: Bool {
        moves.contains { $0.usable && $0.def.damageClass != .status && $0.def.isDamaging }
    }

    var isFainted: Bool { currentHP <= 0 }

    struct MoveSlot: Codable, Identifiable, Sendable, Equatable {
        var id: String { def.name }
        var def: MoveDef
        var ppLeft: Int
        var usable: Bool { ppLeft > 0 }
    }

    func stat(_ s: Stat) -> Int { stats[s] ?? 1 }

    /// 랭크 보정이 적용된 실효 스탯
    func effective(_ s: Stat) -> Int {
        let base = Double(stat(s))
        var v = base * Battler.stageMultiplier(stages[s] ?? 0)
        // 화상은 물리 공격을 절반으로, 마비는 스피드를 절반으로
        if s == .attack, status == .burn { v *= 0.5 }
        if s == .speed, status == .paralysis { v *= 0.5 }
        return max(1, Int(v))
    }

    static func stageMultiplier(_ stage: Int) -> Double {
        let s = max(-6, min(6, stage))
        return s >= 0 ? Double(2 + s) / 2.0 : 2.0 / Double(2 - s)
    }

    static func accEvaMultiplier(_ stage: Int) -> Double {
        let s = max(-6, min(6, stage))
        return s >= 0 ? Double(3 + s) / 3.0 : 3.0 / Double(3 - s)
    }

    // MARK: 생성

    /// 원작 스탯 공식 (개체값 31, 노력치 0)
    static func computeStats(base: SpeciesDef, nature: Nature, level: Int) -> (hp: Int, others: [Stat: Int]) {
        let iv = 31, ev = 0
        func other(_ s: Stat) -> Int {
            let inner = (2 * base.base(s) + iv + ev / 4) * level / 100 + 5
            return max(1, Int(Double(inner) * nature.multiplier(for: s)))
        }
        let hp = (2 * base.base(.hp) + iv + ev / 4) * level / 100 + level + 10
        var m: [Stat: Int] = [:]
        for s in [Stat.attack, .defense, .spAttack, .spDefense, .speed] { m[s] = other(s) }
        return (max(1, hp), m)
    }

    static func make(slot: RosterSlot, species: SpeciesDef, moves: [MoveDef], level: Int,
                     heldItem: ItemDef? = nil, ability: AbilityDef? = nil,
                     form: FormStats? = nil, formName: String? = nil) -> Battler {
        let nature = Nature.named(slot.nature)
        // 폼을 골랐으면 그 폼의 종족값·타입으로 만든다 (로토무 히트 등)
        var base = species
        if let form {
            base.baseStats = form.baseStats
            base.types = form.types
        }
        let (hp, others) = computeStats(base: base, nature: nature, level: level)
        var b = Battler(
            id: slot.id,
            speciesID: slot.speciesID,
            name: species.display + (formName.map { " (\(FormChange.label($0)))" } ?? ""),
            types: base.types,
            level: level,
            natureName: nature.ko,
            isShiny: slot.isShiny,
            fullyEvolved: slot.fullyEvolved,
            maxHP: hp,
            currentHP: hp,
            stats: others,
            moves: moves.map { .init(def: $0, ppLeft: $0.pp) },
            heldItem: heldItem,
            ability: ability,
            weight: species.weight,
            megaForms: species.megaForms,
            gmaxForm: species.gmaxForm,
            baseMaxHP: hp
        )
        b.chosenForm = formName
        b.baseStatsSnapshot = others
        b.baseTypesSnapshot = base.types
        return b
    }

    /// 메가진화 — 타입과 종족값이 바뀐다. HP 는 원작과 같이 그대로 둔다
    /// (모든 메가 폼은 기본 폼과 HP 종족값이 동일하다).
    /// 원시회귀. 메가와 계산은 같지만 **1회 제한이 없고 자동**이며,
    /// isMega 를 세우지 않는다 (메가 슬롯을 쓰지 않기 때문).
    mutating func applyPrimal(form: FormStats, nature: Nature) {
        let iv = 31
        func other(_ s: Stat) -> Int {
            let inner = (2 * form.base(s) + iv) * level / 100 + 5
            return max(1, Int(Double(inner) * nature.multiplier(for: s)))
        }
        for s in [Stat.attack, .defense, .spAttack, .spDefense, .speed] { stats[s] = other(s) }
        types = form.types
        visualForm = form.name
        formLabel = "원시"
        isPrimal = true
    }

    mutating func applyMega(form: FormStats, nature: Nature) {
        let iv = 31
        func other(_ s: Stat) -> Int {
            let inner = (2 * form.base(s) + iv) * level / 100 + 5
            return max(1, Int(Double(inner) * nature.multiplier(for: s)))
        }
        for s in [Stat.attack, .defense, .spAttack, .spDefense, .speed] { stats[s] = other(s) }
        types = form.types
        isMega = true
        visualForm = form.name
        formLabel = form.suffixLabel
    }

    /// 다이맥스 / 거다이맥스 — HP 상한과 현재 HP 가 배율만큼 늘고, 정해진 턴 뒤 되돌아간다.
    /// `form` 이 있으면 거다이맥스(전용 폼)로, 없으면 일반 다이맥스로 발동한다.
    mutating func applyDynamax(form: FormStats?, gigantamax: Bool, turns: Int, multiplier: Double) {
        if baseMaxHP == 0 { baseMaxHP = maxHP }
        let ratio = maxHP > 0 ? Double(currentHP) / Double(maxHP) : 1.0
        maxHP = max(1, Int(Double(baseMaxHP) * multiplier))
        currentHP = max(1, Int(Double(maxHP) * ratio))
        // 거다이맥스는 전용 폼의 타입을 따른다 (대개 원래와 같다)
        if gigantamax, let form {
            types = form.types
            visualForm = form.name          // 거다이맥스는 전용 스프라이트가 있다
        }
        // 거다이맥스면 전용기를 부여한다
        if gigantamax { gmaxMove = GMaxMove.forSpecies(speciesID) }
        dynamaxTurnsLeft = turns
        isGigantamaxed = gigantamax
        formLabel = gigantamax ? "거다이맥스" : "다이맥스"
    }

    /// 배틀 중 자동 변신 (캐스퐁·불비달마·체리꼬·약어리).
    /// HP 는 건드리지 않고 타입·종족값만 바꾼다.
    mutating func applyAutoForm(_ name: String?, stats: FormStats?, nature: Nature) {
        guard autoForm != name else { return }
        autoForm = name
        if let stats {
            let iv = 31
            for s in [Stat.attack, .defense, .spAttack, .spDefense, .speed] {
                let inner = (2 * stats.base(s) + iv) * level / 100 + 5
                self.stats[s] = max(1, Int(Double(inner) * nature.multiplier(for: s)))
            }
            types = stats.types
        } else {
            // 원래대로
            stats0Restore()
        }
    }

    private mutating func stats0Restore() {
        if !baseStatsSnapshot.isEmpty { stats = baseStatsSnapshot }
        if !baseTypesSnapshot.isEmpty { types = baseTypesSnapshot }
    }

    /// 다이맥스 해제 — HP 상한이 줄고 현재 HP 도 비율에 맞춰 줄어든다.
    ///
    /// `isDynamaxed` 로 가드하면 안 된다: 호출부가 dynamaxTurnsLeft 를 0 으로 깎은 뒤
    /// 부르기 때문에 가드가 자기 자신을 막아 HP 상한이 늘어난 채로 남는다.
    mutating func revertDynamax() {
        dynamaxTurnsLeft = 0
        isGigantamaxed = false
        gmaxMove = nil
        if !isMega {
            formLabel = nil
            visualForm = nil      // 거다이맥스 스프라이트를 원래대로
        }
        guard baseMaxHP > 0, maxHP != baseMaxHP else { return }

        // **쓰러진 개체는 절대 되살리지 않는다.**
        // 예전에는 max(1, ...) 때문에 다이맥스 중 쓰러진 포켓몬이 해제될 때
        // HP 1 로 부활했고, "종료됐는데 양쪽 다 생존" 상태가 만들어졌다.
        let wasFainted = currentHP <= 0
        let ratio = maxHP > 0 ? Double(currentHP) / Double(maxHP) : 1.0
        maxHP = max(1, baseMaxHP)
        if wasFainted {
            currentHP = 0
        } else {
            currentHP = max(1, min(maxHP, Int(Double(maxHP) * ratio)))
        }
    }
}
