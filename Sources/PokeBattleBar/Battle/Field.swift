import Foundation

/// 날씨. PokeAPI 는 날씨 기술을 `whole-field-effect` 로만 알려주고
/// 어떤 날씨인지는 주지 않으므로, 기술 이름 → 날씨 표를 직접 둔다.
enum Weather: String, Codable, Sendable {
    case none, sun, rain, sandstorm, snow

    var ko: String {
        switch self {
        case .none: "-"; case .sun: "쾌청"; case .rain: "비"
        case .sandstorm: "모래바람"; case .snow: "싸라기눈"
        }
    }

    /// 날씨에 따른 타입별 데미지 배율 (원작 규칙)
    func damageMultiplier(for type: PType) -> Double {
        switch self {
        case .sun:  return type == .fire ? 1.5 : (type == .water ? 0.5 : 1.0)
        case .rain: return type == .water ? 1.5 : (type == .fire ? 0.5 : 1.0)
        default:    return 1.0
        }
    }

    /// 모래바람 지속 피해를 받지 않는 타입
    func isImmuneToChip(_ types: [PType]) -> Bool {
        switch self {
        case .sandstorm: return types.contains(.rock) || types.contains(.ground) || types.contains(.steel)
        case .snow:      return true              // 8세대 이후 눈은 지속 피해가 없다
        default:         return true
        }
    }

    static func from(moveName: String) -> Weather? {
        switch moveName {
        case "sunny-day":  return .sun
        case "rain-dance": return .rain
        case "sandstorm":  return .sandstorm
        case "hail", "snowscape", "chilly-reception": return .snow
        default:           return nil
        }
    }
}

/// 필드(테라인). 날씨와 별개로 걸린다.
enum Terrain: String, Codable, Sendable {
    case none, electric, grassy, misty, psychic

    var ko: String {
        switch self {
        case .none: "-"; case .electric: "일렉트릭필드"; case .grassy: "그래스필드"
        case .misty: "미스트필드"; case .psychic: "사이코필드"
        }
    }

    static func from(moveName: String) -> Terrain? {
        switch moveName {
        case "electric-terrain": return .electric
        case "grassy-terrain":   return .grassy
        case "misty-terrain":    return .misty
        case "psychic-terrain":  return .psychic
        default:                 return nil
        }
    }

    /// 필드 위 포켓몬의 기술 강화 (땅에 붙어 있는 경우)
    func boost(for type: PType) -> Double {
        switch (self, type) {
        case (.electric, .electric), (.grassy, .grass), (.psychic, .psychic): return 1.3
        default: return 1.0
        }
    }
}

/// 등장 시 피해를 주는 장애물.
/// **교체가 없어도 의미가 있다** — 이 게임에는 "쓰러지면 다음 포켓몬 등장" 이라는 등장 시점이 있다.
/// 교체룰이 들어오면 그대로 교체 시에도 작동한다.
enum Hazard: String, Codable, Sendable, CaseIterable {
    case stealthRock      // 다이맥스스톤즈 — 바위 상성 기반 피해
    case steelSurge       // 다이맥스스틸 — 강철 상성 기반 피해

    var ko: String {
        switch self {
        case .stealthRock: "스텔스록"
        case .steelSurge:  "스틸록"
        }
    }
    /// 상성 계산에 쓰는 타입
    var type: PType {
        switch self {
        case .stealthRock: .rock
        case .steelSurge:  .steel
        }
    }
    /// 등장 시 피해 = 최대HP × 상성배율 / 8
    func damage(maxHP: Int, multiplier: Double) -> Int {
        max(1, Int(Double(maxHP) * multiplier / 8.0))
    }
}

/// 배틀 필드 상태
struct FieldState: Codable, Sendable, Equatable {
    var weather: Weather = .none
    var weatherTurns: Int = 0
    var terrain: Terrain = .none
    var terrainTurns: Int = 0
    /// 중력 — 부유·비행 무효, 명중률 상승
    var gravityTurns: Int = 0

    var hasWeather: Bool { weather != .none && weatherTurns > 0 }
    var hasTerrain: Bool { terrain != .none && terrainTurns > 0 }
    var hasGravity: Bool { gravityTurns > 0 }

    mutating func setGravity(_ turns: Int) { gravityTurns = turns }

    mutating func setWeather(_ w: Weather, turns: Int = 5) {
        weather = w; weatherTurns = turns
    }
    mutating func setTerrain(_ t: Terrain, turns: Int = 5) {
        terrain = t; terrainTurns = turns
    }
    /// 턴 종료 시 감소. 끝난 것들을 돌려준다 (로그용).
    mutating func tick() -> (endedWeather: Weather?, endedTerrain: Terrain?, gravityEnded: Bool) {
        var ew: Weather?, et: Terrain?, eg = false
        if weatherTurns > 0 {
            weatherTurns -= 1
            if weatherTurns == 0 { ew = weather; weather = .none }
        }
        if terrainTurns > 0 {
            terrainTurns -= 1
            if terrainTurns == 0 { et = terrain; terrain = .none }
        }
        if gravityTurns > 0 {
            gravityTurns -= 1
            if gravityTurns == 0 { eg = true }
        }
        return (ew, et, eg)
    }
}

/// 기술 플래그. **PokeAPI 가 주지 않는 정보**라 직접 표로 관리한다.
/// 접촉 판정은 정전기·불꽃몸·거친피부 같은 특성 다수가 요구한다.
enum MoveFlags {
    /// 접촉하는 기술. 원작 접촉 기술 중 이 엔진에서 실제로 쓰일 만한 것들.
    static let contact: Set<String> = [
        "tackle", "body-slam", "double-edge", "take-down", "quick-attack", "extreme-speed",
        "scratch", "cut", "slash", "night-slash", "false-swipe", "fury-cutter", "x-scissor",
        "pound", "slam", "strength", "headbutt", "skull-bash", "zen-headbutt", "iron-head",
        "bite", "crunch", "fire-fang", "thunder-fang", "ice-fang", "poison-fang", "psychic-fangs",
        "punch", "mega-punch", "fire-punch", "ice-punch", "thunder-punch", "drain-punch",
        "mach-punch", "bullet-punch", "shadow-punch", "dynamic-punch", "focus-punch",
        "close-combat", "brick-break", "karate-chop", "cross-chop", "hammer-arm", "superpower",
        "low-kick", "high-jump-kick", "jump-kick", "double-kick", "blaze-kick", "triple-kick",
        "mega-kick", "rolling-kick", "aerial-ace", "wing-attack", "brave-bird", "drill-peck",
        "peck", "fury-attack", "horn-attack", "megahorn", "gore", "wild-charge", "volt-tackle",
        "flare-blitz", "u-turn", "flame-wheel", "flame-charge", "leech-life", "giga-drain-no",
        "waterfall", "aqua-tail", "aqua-jet", "dive", "dragon-claw", "dragon-rush", "outrage",
        "play-rough", "poison-jab", "gunk-shot-no", "seismic-toss", "vine-whip", "power-whip",
        "petal-blizzard-no", "leaf-blade", "wood-hammer", "seed-bomb-no", "bullet-seed-no",
        "shadow-claw", "shadow-force", "phantom-force", "sucker-punch", "pursuit", "knock-off",
        "thief", "covet", "double-slap", "comet-punch", "arm-thrust", "rock-climb",
        "steel-wing", "metal-claw", "bullet-punch-no", "iron-tail", "double-iron-bash",
        "avalanche", "ice-shard-no", "icicle-crash-no", "liquidation", "crabhammer",
        "first-impression", "lunge", "smart-strike", "zing-zap", "assurance", "revenge",
        "counter", "reversal", "flail", "return", "frustration", "facade", "retaliate",
        "giga-impact", "explosion-no", "self-destruct-no", "struggle"
    ].filter { !$0.hasSuffix("-no") }.reduce(into: Set<String>()) { $0.insert($1) }

    /// 펀치 기술 (철주먹)
    static let punch: Set<String> = [
        "mega-punch", "fire-punch", "ice-punch", "thunder-punch", "drain-punch",
        "mach-punch", "bullet-punch", "shadow-punch", "dynamic-punch", "focus-punch",
        "comet-punch", "dizzy-punch", "hammer-arm", "sky-uppercut", "power-up-punch",
        "meteor-mash", "double-iron-bash", "plasma-fists", "ice-hammer"
    ]

    /// 물기 기술 (옹골찬턱)
    static let bite: Set<String> = [
        "bite", "crunch", "fire-fang", "thunder-fang", "ice-fang", "poison-fang",
        "psychic-fangs", "hyper-fang", "super-fang", "fishious-rend", "jaw-lock"
    ]

    /// 소리 기술 (방음)
    static let sound: Set<String> = [
        "hyper-voice", "boomburst", "bug-buzz", "snarl", "round", "echoed-voice",
        "uproar", "screech", "growl", "roar", "sing", "supersonic", "metal-sound",
        "disarming-voice", "overdrive", "clanging-scales", "sparkling-aria"
    ]

    /// 가루 기술 (방진·풀타입 면역)
    static let powder: Set<String> = [
        "sleep-powder", "stun-spore", "poison-powder", "spore", "cotton-spore",
        "rage-powder", "powder", "magic-powder"
    ]

    /// 방어 기술 (다이맥스일격/연격이 관통한다)
    static let protect: Set<String> = [
        "protect", "detect", "spiky-shield", "kings-shield", "baneful-bunker",
        "obstruct", "silk-trap", "burning-bulwark"
    ]

    static func isProtect(_ name: String) -> Bool { protect.contains(name) }
    static func isContact(_ name: String) -> Bool { contact.contains(name) }
    static func isPunch(_ name: String) -> Bool { punch.contains(name) }
    static func isBite(_ name: String) -> Bool { bite.contains(name) }
    static func isSound(_ name: String) -> Bool { sound.contains(name) }
    static func isPowder(_ name: String) -> Bool { powder.contains(name) }
}
