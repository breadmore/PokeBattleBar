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
    /// 거다이맥스 남은 턴수 (0 이면 평상시)
    var gmaxTurnsLeft: Int = 0
    /// 변신 표시용 라벨 ("메가 X", "거다이맥스")
    var formLabel: String?
    /// 거다이맥스 해제 시 되돌릴 원래 HP 상한
    var baseMaxHP: Int = 0

    var isGmax: Bool { gmaxTurnsLeft > 0 }
    var canMega: Bool { !megaForms.isEmpty && !isMega }
    var canGmax: Bool { gmaxForm != nil && !isGmax }

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

    static func make(slot: RosterSlot, species: SpeciesDef, moves: [MoveDef], level: Int) -> Battler {
        let nature = Nature.named(slot.nature)
        let (hp, others) = computeStats(base: species, nature: nature, level: level)
        return Battler(
            id: slot.id,
            speciesID: slot.speciesID,
            name: species.display,
            types: species.types,
            level: level,
            natureName: nature.ko,
            isShiny: slot.isShiny,
            fullyEvolved: slot.fullyEvolved,
            maxHP: hp,
            currentHP: hp,
            stats: others,
            moves: moves.map { .init(def: $0, ppLeft: $0.pp) },
            megaForms: species.megaForms,
            gmaxForm: species.gmaxForm,
            baseMaxHP: hp
        )
    }

    /// 메가진화 — 타입과 종족값이 바뀐다. HP 는 원작과 같이 그대로 둔다
    /// (모든 메가 폼은 기본 폼과 HP 종족값이 동일하다).
    mutating func applyMega(form: FormStats, nature: Nature) {
        let iv = 31
        func other(_ s: Stat) -> Int {
            let inner = (2 * form.base(s) + iv) * level / 100 + 5
            return max(1, Int(Double(inner) * nature.multiplier(for: s)))
        }
        for s in [Stat.attack, .defense, .spAttack, .spDefense, .speed] { stats[s] = other(s) }
        types = form.types
        isMega = true
        formLabel = form.suffixLabel
    }

    /// 거다이맥스 — HP 상한과 현재 HP 가 배율만큼 늘고, 정해진 턴 뒤 되돌아간다.
    mutating func applyGmax(form: FormStats?, turns: Int, multiplier: Double) {
        if baseMaxHP == 0 { baseMaxHP = maxHP }
        let ratio = maxHP > 0 ? Double(currentHP) / Double(maxHP) : 1.0
        maxHP = max(1, Int(Double(baseMaxHP) * multiplier))
        currentHP = max(1, Int(Double(maxHP) * ratio))
        if let form { types = form.types }
        gmaxTurnsLeft = turns
        formLabel = "거다이맥스"
    }

    /// 거다이맥스 해제 — HP 상한이 줄고 현재 HP 도 비율에 맞춰 줄어든다.
    ///
    /// `isGmax` 로 가드하면 안 된다: 호출부가 gmaxTurnsLeft 를 0 으로 깎은 뒤 부르기 때문에
    /// 가드가 자기 자신을 막아 HP 상한이 늘어난 채로 남는다.
    mutating func revertGmax() {
        gmaxTurnsLeft = 0
        if !isMega { formLabel = nil }
        guard baseMaxHP > 0, maxHP != baseMaxHP else { return }
        let ratio = maxHP > 0 ? Double(currentHP) / Double(maxHP) : 1.0
        maxHP = max(1, baseMaxHP)
        currentHP = max(1, min(maxHP, Int(Double(maxHP) * ratio)))
    }
}
