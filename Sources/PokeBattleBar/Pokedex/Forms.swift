import Foundation

/// 한 배틀에서 **플레이어당 각각 한 번씩만** 쓸 수 있는 특수 변신.
/// 6마리를 데려갔다면 한 마리는 메가, 다른 한 마리는 거다이맥스, 또 한 마리는 Z기술 —
/// 여섯 마리가 모두 거다이맥스할 수는 없다.
enum SpecialAction: Codable, Hashable, Sendable {
    case mega(form: String)     // 메가스톤 — 폼 이름 (리자몽은 X/Y 선택)
    case gmax                   // 거다이맥스
    case zMove                  // Z기술 (이번 공격 한 번만)

    var ko: String {
        switch self {
        case .mega:  "메가진화"
        case .gmax:  "거다이맥스"
        case .zMove: "Z기술"
        }
    }
}

/// 타입 → Z기술 / 맥스기술 이름. PokeAPI 에 전부 존재하는 것을 확인했다.
enum FormTables {

    static let zMoveBase: [PType: String] = [
        .normal: "breakneck-blitz",       .fighting: "all-out-pummeling",
        .flying: "supersonic-skystrike",  .poison: "acid-downpour",
        .ground: "tectonic-rage",         .rock: "continental-crush",
        .bug: "savage-spin-out",          .ghost: "never-ending-nightmare",
        .steel: "corkscrew-crash",        .fire: "inferno-overdrive",
        .water: "hydro-vortex",           .grass: "bloom-doom",
        .electric: "gigavolt-havoc",      .psychic: "shattered-psyche",
        .ice: "subzero-slammer",          .dragon: "devastating-drake",
        .dark: "black-hole-eclipse",      .fairy: "twinkle-tackle"
    ]

    static let maxMove: [PType: String] = [
        .normal: "max-strike",      .fire: "max-flare",         .water: "max-geyser",
        .electric: "max-lightning", .grass: "max-overgrowth",   .ice: "max-hailstorm",
        .fighting: "max-knuckle",   .poison: "max-ooze",        .ground: "max-quake",
        .flying: "max-airstream",   .psychic: "max-mindstorm",  .bug: "max-flutterby",
        .rock: "max-rockfall",      .ghost: "max-phantasm",     .dragon: "max-wyrmwind",
        .dark: "max-darkness",      .steel: "max-steelspike",   .fairy: "max-starfall"
    ]

    static let maxGuard = "max-guard"

    /// Z기술 이름 (물리/특수 구분). PokeAPI 는 `--physical` / `--special` 로 나뉘어 있다.
    static func zMoveName(for move: MoveDef) -> String? {
        guard let base = zMoveBase[move.type] else { return nil }
        switch move.damageClass {
        case .physical: return "\(base)--physical"
        case .special:  return "\(base)--special"
        case .status:   return nil          // 변화기는 Z기술로 바뀌지 않는다 (Z파워는 별도 효과)
        }
    }

    /// 원작 Z기술 위력 변환표. PokeAPI 는 Z기술 위력을 주지 않는다 (power=None).
    static func zPower(basePower: Int) -> Int {
        switch basePower {
        case ...55:      return 100
        case 56...65:    return 120
        case 66...75:    return 140
        case 76...85:    return 160
        case 86...95:    return 175
        case 96...100:   return 180
        case 101...110:  return 185
        case 111...125:  return 190
        case 126...130:  return 195
        default:         return 200
        }
    }

    /// 원작 맥스기술 위력 변환표. 격투·독 타입은 낮은 표를 쓴다.
    static func maxPower(basePower: Int, type: PType) -> Int {
        let low = (type == .fighting || type == .poison)
        switch basePower {
        case ...40:      return low ? 70  : 90
        case 41...50:    return low ? 75  : 100
        case 51...60:    return low ? 80  : 110
        case 61...75:    return low ? 85  : 120
        case 76...85:    return low ? 90  : 130
        case 86...95:    return low ? 95  : 140
        default:         return low ? 100 : 150
        }
    }

    /// 거다이맥스 지속 턴수와 HP 배율 (원작 기준)
    static let gmaxTurns = 3
    static let gmaxHPMultiplier = 1.5
}

/// UI 에서 다루기 쉬운 변신 종류 (폼 이름 없이 종류만)
enum SpecialKind: String, CaseIterable, Sendable {
    case mega, gmax, zMove
    var ko: String {
        switch self {
        case .mega:  "메가진화"
        case .gmax:  "거다이맥스"
        case .zMove: "Z기술"
        }
    }
    var icon: String {
        switch self {
        case .mega:  "✦"
        case .gmax:  "◈"
        case .zMove: "⚡"
        }
    }
}
