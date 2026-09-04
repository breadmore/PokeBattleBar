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

/// 기술 플래그.
///
/// **예전에는 PokeAPI 가 주지 않아 손으로 목록을 관리했다.**
/// 이제 Showdown 데이터(954개 기술, 접촉 278·펀치 24·물기 10·소리 33·가루 8)를 쓴다 —
/// 수기 목록은 빠뜨리면 조용히 버그가 되지만, 이건 원본 그대로다.
enum MoveFlags {
    static func isContact(_ name: String) -> Bool { Showdown.move(name)?.isContact ?? false }
    static func isPunch(_ name: String) -> Bool { Showdown.move(name)?.isPunch ?? false }
    static func isBite(_ name: String) -> Bool { Showdown.move(name)?.isBite ?? false }
    static func isSound(_ name: String) -> Bool { Showdown.move(name)?.isSound ?? false }
    static func isPowder(_ name: String) -> Bool { Showdown.move(name)?.isPowder ?? false }

    /// 방어 기술 자체인가 (우선도 +4 로 자신을 지킨다)
    static func isProtect(_ name: String) -> Bool {
        // Showdown 은 방어 계열을 stallingMove 로 표시하지만 축약 데이터에 넣지 않았다.
        // 종류가 적고 확정적이라 목록으로 둔다.
        protectMoves.contains(name)
    }
    static let protectMoves: Set<String> = [
        "protect", "detect", "spiky-shield", "kings-shield", "baneful-bunker",
        "obstruct", "silk-trap", "burning-bulwark", "max-guard"
    ]

    /// 이 기술이 상대의 방어를 뚫는가 (Showdown 의 protect 플래그가 없으면 관통)
    static func bypassesProtect(_ name: String) -> Bool {
        guard let m = Showdown.move(name) else { return false }
        return !m.blockedByProtect
    }

    /// 쓴 뒤 자신이 교체되는 기술 (유턴·볼트체인지·퀵턴·배턴터치)
    static func isSelfSwitch(_ name: String) -> Bool { Showdown.move(name)?.selfSwitch ?? false }
    /// 쓴 쪽이 쓰러지는 기술 (대폭발·자폭·목숨걸기·메멘토)
    static func isSelfDestruct(_ name: String) -> Bool { Showdown.move(name)?.selfDestruct ?? false }
    /// 솔라빔처럼 모으는 턴이 있는 기술인가
    static func isCharge(_ name: String) -> Bool { Showdown.move(name)?.isCharge ?? false }
    /// 난동부리기처럼 여러 턴 조작할 수 없게 되는 기술인가
    static func locksUser(_ name: String) -> Bool { Showdown.move(name)?.locksUser ?? false }
    /// 일격필살인가 (땅가르기·뿔드릴·절대영도·가위자르기)
    static func isOHKO(_ name: String) -> Bool { Showdown.move(name)?.ohko ?? false }
    /// 모으는 동안 몸을 숨기는가 (땅속·공중·물속)
    static func chargeHides(_ name: String) -> Bool { Showdown.move(name)?.hidesUser ?? false }
    /// 파괴광선처럼 쓴 다음 턴에 못 움직이는가
    static func mustRecharge(_ name: String) -> Bool { Showdown.move(name)?.mustRecharge ?? false }
    /// 공격 **판정보다 먼저** 쓰러지는 기술인가 (대폭발 계열만).
    /// 목숨걸기는 자기 HP 만큼 데미지를 주므로 먼저 쓰러지면 위력이 0 이 된다.
    static func selfDestructsBeforeMove(_ name: String) -> Bool {
        Showdown.move(name)?.selfDestructBeforeMove ?? false
    }
}
