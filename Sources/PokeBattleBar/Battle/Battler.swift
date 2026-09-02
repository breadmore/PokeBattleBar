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
            moves: moves.map { .init(def: $0, ppLeft: $0.pp) }
        )
    }
}
