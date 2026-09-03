import Foundation

/// 거다이맥스 전용 G-Max 기술.
///
/// **PokeAPI 에는 G-Max 기술이 하나도 없다** (기술 937개 중 0개, 직접 조회는 404).
/// 그래서 종 → 전용기 표를 직접 둔다. 위력은 일반 맥스 기술과 같은 변환표를 쓰고,
/// 다른 점은 **추가 효과**다.
enum GMaxMove: String, Codable, Sendable {
    case vineLash, wildfire, cannonade, befuddle, voltCrash, goldRush, chiStrike
    case terror, foamBurst, resonance, cuddle, replenish, malodor, meltdown
    case drumSolo, fireball, hydrosnipe, windRage, gravitas, stonesurge, volcalith
    case tartness, sweetness, sandblast, stunShock, centiferno, smite, snooze
    case finale, steelsurge, depletion, oneBlow, rapidFlow

    var ko: String {
        switch self {
        case .vineLash:   "다이맥스채찍"
        case .wildfire:   "다이맥스파이어"
        case .cannonade:  "다이맥스포"
        case .befuddle:   "다이맥스인섹트"
        case .voltCrash:  "다이맥스썬더"
        case .goldRush:   "다이맥스코인"
        case .chiStrike:  "다이맥스태클"
        case .terror:     "다이맥스고스트"
        case .foamBurst:  "다이맥스버블"
        case .resonance:  "다이맥스싱"
        case .cuddle:     "다이맥스하트"
        case .replenish:  "다이맥스이팅"
        case .malodor:    "다이맥스스모그"
        case .meltdown:   "다이맥스멜트"
        case .drumSolo:   "다이맥스드럼솔로"
        case .fireball:   "다이맥스발리"
        case .hydrosnipe: "다이맥스스나이프"
        case .windRage:   "다이맥스윈드"
        case .gravitas:   "다이맥스그래비티"
        case .stonesurge: "다이맥스스톤즈"
        case .volcalith:  "다이맥스버스트"
        case .tartness:   "다이맥스사우어"
        case .sweetness:  "다이맥스스위트"
        case .sandblast:  "다이맥스샌드"
        case .stunShock:  "다이맥스스파크"
        case .centiferno: "다이맥스센티퍼노"
        case .smite:      "다이맥스매직"
        case .snooze:     "다이맥스스노즈"
        case .finale:     "다이맥스피날레"
        case .steelsurge: "다이맥스스틸"
        case .depletion:  "다이맥스디플리션"
        case .oneBlow:    "다이맥스일격"
        case .rapidFlow:  "다이맥스연격"
        }
    }

    var type: PType {
        switch self {
        case .vineLash, .drumSolo, .tartness, .sweetness: .grass
        case .wildfire, .fireball, .centiferno:           .fire
        case .cannonade, .hydrosnipe, .foamBurst, .stonesurge, .rapidFlow: .water
        case .befuddle:                                   .bug
        case .voltCrash, .stunShock:                      .electric
        case .goldRush, .cuddle, .replenish:              .normal
        case .chiStrike:                                  .fighting
        case .terror:                                     .ghost
        case .resonance:                                  .ice
        case .malodor:                                    .poison
        case .meltdown, .steelsurge:                      .steel
        case .windRage:                                   .flying
        case .gravitas, .smite:                           .psychic
        case .volcalith:                                  .rock
        case .sandblast:                                  .ground
        case .snooze, .oneBlow:                           .dark
        case .depletion:                                  .dragon
        case .finale:                                     .fairy
        }
    }

    /// 이 엔진에서 실제로 재현되는 추가 효과
    var effect: GMaxEffect {
        switch self {
        // 4턴간 특정 타입이 아닌 상대에게 최대 HP 1/6 지속 피해
        case .vineLash:   .damageOverTime(immuneType: .grass, turns: 4)
        case .wildfire:   .damageOverTime(immuneType: .fire, turns: 4)
        case .cannonade:  .damageOverTime(immuneType: .water, turns: 4)
        case .volcalith:  .damageOverTime(immuneType: .rock, turns: 4)
        case .centiferno: .damageOverTime(immuneType: .fire, turns: 4)
        case .sandblast:  .damageOverTime(immuneType: .ground, turns: 4)

        // 상태이상
        case .voltCrash:  .inflict(.paralysis)
        case .malodor:    .inflict(.poison)
        case .stunShock:  .inflictRandom([.poison, .paralysis])
        case .befuddle:   .inflictRandom([.poison, .paralysis, .sleep])
        case .snooze:     .inflict(.sleep)
        case .goldRush:   .inflict(.confusion)
        case .smite:      .inflict(.confusion)
        case .cuddle:     .inflict(.confusion)     // 헤롱헤롱 대용 (혼란으로 재현)

        // 능력치
        case .foamBurst:  .foeStat(.speed, -2)
        case .tartness:   .foeEvasion(-1)
        case .chiStrike:  .selfCrit(2)
        case .drumSolo, .fireball, .hydrosnipe: .ignoreAbility

        // 회복 / 기타
        case .finale:     .healSelf(percent: 16)
        case .sweetness:  .cureStatus
        case .replenish:  .healSelf(percent: 12)
        case .depletion:  .drainPP(3)
        case .resonance:  .selfStat(.defense, 1)   // 오로라베일 대용 (방어 상승으로 재현)

        // 이 엔진에 대응 개념이 없는 것 (교체가 없어 스텔스록·묶기·중력이 무의미)
        case .terror, .windRage, .gravitas, .stonesurge, .steelsurge,
             .meltdown, .oneBlow, .rapidFlow:
            .none
        }
    }

    /// 종 ID → 전용기
    static func forSpecies(_ id: Int) -> GMaxMove? { table[id] }

    private static let table: [Int: GMaxMove] = [
        3: .vineLash,      6: .wildfire,     9: .cannonade,   12: .befuddle,
        25: .voltCrash,   52: .goldRush,    68: .chiStrike,   94: .terror,
        99: .foamBurst,  131: .resonance,  133: .cuddle,     143: .replenish,
        569: .malodor,   809: .meltdown,   812: .drumSolo,   815: .fireball,
        818: .hydrosnipe,823: .windRage,   826: .gravitas,   834: .stonesurge,
        839: .volcalith, 841: .tartness,   842: .sweetness,  844: .sandblast,
        849: .stunShock, 851: .centiferno, 858: .smite,      861: .snooze,
        869: .finale,    879: .steelsurge, 884: .depletion,  892: .oneBlow
    ]

    /// 표에 등록된 거다이맥스 종 수
    static var speciesCount: Int { table.count }
}

/// G-Max 기술의 추가 효과
enum GMaxEffect: Codable, Hashable, Sendable {
    case none
    case damageOverTime(immuneType: PType, turns: Int)
    case inflict(Ailment)
    case inflictRandom([Ailment])
    case foeStat(Stat, Int)
    case foeEvasion(Int)
    case selfStat(Stat, Int)
    case selfCrit(Int)
    case healSelf(percent: Int)
    case cureStatus
    case drainPP(Int)
    case ignoreAbility

    /// 이 엔진에서 실제로 재현되는가
    var isImplemented: Bool { self != .none }

    var ko: String {
        switch self {
        case .none:                          "추가 효과 없음"
        case .damageOverTime(let t, let n):  "\(n)턴간 \(t.ko)타입이 아닌 상대에게 지속 피해"
        case .inflict(let a):                "상대를 \(a.ko) 상태로"
        case .inflictRandom(let a):          "상대를 \(a.map(\.ko).joined(separator: "/")) 중 하나로"
        case .foeStat(let s, let n):         "상대 \(s.ko) \(n > 0 ? "+" : "")\(n)"
        case .foeEvasion(let n):             "상대 회피 \(n > 0 ? "+" : "")\(n)"
        case .selfStat(let s, let n):        "자신 \(s.ko) \(n > 0 ? "+" : "")\(n)"
        case .selfCrit(let n):               "자신 급소율 +\(n)"
        case .healSelf(let p):               "자신 HP \(p)% 회복"
        case .cureStatus:                    "자신 상태이상 회복"
        case .drainPP(let n):                "상대 기술 PP \(n) 감소"
        case .ignoreAbility:                 "상대 특성 무시"
        }
    }
}
