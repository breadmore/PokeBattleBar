import Foundation

/// 특성의 **배틀에서 실제로 작동하는** 효과.
///
/// PokeAPI 는 373개 특성을 이름·한글명·효과 텍스트로 주지만 효과는 산문이다.
/// 그래서 모든 특성을 **표시**는 하되, 아래에 구조화한 것만 **실제로 계산에 반영**한다.
/// (특성별 개별 구현이 필요하고, 날씨·접촉 판정처럼 이 엔진에 없는 개념에 의존하는 것도 많다)
enum AbilityKind: Codable, Hashable, Sendable {
    case none                                   // 표시만 (미구현)

    case pinchBoost(PType, Double)              // 맹화/급류/신록/벌레의야망 — HP 1/3 이하에서 해당 타입 강화
    case intimidate                             // 위협 — 등장 시 상대 공격 -1
    case typeImmunity(PType)                    // 부유 — 해당 타입 무효
    case sturdy                                 // 옹골참 — 풀피에서 일격 방지
    case damageTaken([PType], Double)           // 두꺼운지방 — 특정 타입 피해 감소
    case superEffectiveResist(Double)           // 하드록/필터 — 효과 굉장한 피해 감소
    case statusImmunity(Ailment)                // 면역/수의베일/불면 등
    case technician(maxPower: Int, Double)       // 테크니션 — 저위력 기술 강화
    case clearBody                              // 클리어바디 — 능력치 하락 무효
    case noGuard                                // 노가드 — 반드시 명중
    case sheerForce(Double)                     // 우격다짐 — 위력↑, 부가효과 없음
    case tintedLens(Double)                     // 색안경 — 효과 별로인 기술 강화
    case adaptability(Double)                   // 적응력 — 자기타입일치 배율 변경
    case sniper(Double)                          // 스나이퍼 — 급소 배율 변경
    case attackMultiplier(Double)               // 순수한힘/요가파워 — 공격 배율
    case statusDefBoost(Stat, Double)           // 이상한비늘 — 상태이상 시 방어 상승
    case statusAtkBoost(Stat, Double)           // 근성 — 상태이상 시 공격 상승
    case magicGuard                             // 매직가드 — 간접 피해 무효
    case rockHead                               // 돌머리 — 반동 없음
    case reckless(Double)                       // 이판사판 — 반동기 강화
    case scrappy                                // 배짱 — 노말/격투가 고스트에 통함
    case unaware                                // 천진 — 상대 능력치 변화 무시
    case sereneGrace(Double)                    // 하늘의은총 — 부가효과 확률 배수
    case shieldDust                             // 색가루 — 부가효과 받지 않음

    // 날씨 (Field.swift 도입으로 구현 가능해졌다)
    case weatherOnEntry(Weather)                // 가뭄/잔비/모래날림/눈퍼뜨리기
    case weatherSpeedBoost(Weather, Double)     // 엽록소/쓱쓱/모래헤치기/눈치우기
    case weatherStatBoost(Weather, Stat, Double)// 태양의힘/플라워기프트
    case weatherHeal(Weather, Int)              // 아이스바디/우비 — 날씨에 회복
    case weatherEvasion(Weather)                // 모래숨기/눈숨기
    case weatherImmuneChip                      // 모래헤치기 등 — 모래 피해 무효
    case dryskin                                // 건조피부 — 물 흡수, 불꽃 약점

    // 접촉 (MoveFlags 도입으로 구현 가능해졌다)
    case contactStatus(Ailment, percent: Int)   // 정전기/불꽃몸/포자
    case contactDamage(Int)                     // 거친피부/철가시 — 1/N 반사
    case moveFlagBoost(MoveFlagKind, Double)    // 철주먹/옹골찬턱
    case soundImmunity                          // 방음
    case powderImmunity                         // 방진

    // 기타
    case ignoreAbility                          // 틀깨기
    case criticalImmunity                       // 전투무장/조가비갑옷
    case multiscale(Double)                     // 멀티스케일 — 풀피에서 피해 감소
    case levitateLike(PType, Double)            // 저수/축전/타오르는불꽃 — 흡수
}

/// 기술 플래그 종류 (철주먹·옹골찬턱용)
enum MoveFlagKind: String, Codable, Hashable, Sendable {
    case punch, bite, sound, powder, contact
}

struct AbilityDef: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var koName: String
    var shortEffect: String
    var isHidden: Bool = false
    var kind: AbilityKind

    var display: String { koName.isEmpty ? name : koName }
    /// 실제로 배틀 계산에 반영되는가
    var isImplemented: Bool { kind != .none }
}

actor AbilityCatalog {
    static let shared = AbilityCatalog()

    private(set) var abilities: [String: AbilityDef] = [:]
    private let session: URLSession
    private let cacheDir: URL

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
        cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/PokeBattleBar/pokeapi")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// 구조화된 효과 표. 여기에 있는 것만 배틀 계산에 반영된다.
    static func kind(for slug: String) -> AbilityKind {
        switch slug {
        // 궁지 강화
        case "blaze":      return .pinchBoost(.fire, 1.5)
        case "torrent":    return .pinchBoost(.water, 1.5)
        case "overgrow":   return .pinchBoost(.grass, 1.5)
        case "swarm":      return .pinchBoost(.bug, 1.5)

        case "intimidate": return .intimidate
        case "levitate":   return .typeImmunity(.ground)
        case "sturdy":     return .sturdy
        case "thick-fat":  return .damageTaken([.fire, .ice], 0.5)
        case "heatproof":  return .damageTaken([.fire], 0.5)
        case "solid-rock", "filter", "prism-armor": return .superEffectiveResist(0.75)

        // 상태이상 면역
        case "immunity":                  return .statusImmunity(.poison)
        case "water-veil", "water-bubble":return .statusImmunity(.burn)
        case "insomnia", "vital-spirit":  return .statusImmunity(.sleep)
        case "limber":                    return .statusImmunity(.paralysis)
        case "magma-armor":               return .statusImmunity(.freeze)
        case "own-tempo":                 return .statusImmunity(.confusion)

        case "technician": return .technician(maxPower: 60, 1.5)
        case "clear-body", "white-smoke", "full-metal-body": return .clearBody
        case "no-guard":   return .noGuard
        case "sheer-force":return .sheerForce(1.3)
        case "tinted-lens":return .tintedLens(2.0)
        case "adaptability":return .adaptability(2.0)
        case "sniper":     return .sniper(2.25)
        case "huge-power", "pure-power": return .attackMultiplier(2.0)
        case "marvel-scale": return .statusDefBoost(.defense, 1.5)
        case "guts":       return .statusAtkBoost(.attack, 1.5)
        case "magic-guard":return .magicGuard
        case "rock-head":  return .rockHead
        case "reckless":   return .reckless(1.2)
        case "scrappy":    return .scrappy
        case "unaware":    return .unaware
        case "serene-grace": return .sereneGrace(2.0)
        case "shield-dust", "overcoat": return .shieldDust

        // 날씨를 부르는 특성
        case "drought", "orichalcum-pulse":  return .weatherOnEntry(.sun)
        case "drizzle":                      return .weatherOnEntry(.rain)
        case "sand-stream", "sand-spit":     return .weatherOnEntry(.sandstorm)
        case "snow-warning":                 return .weatherOnEntry(.snow)

        // 날씨에서 스피드 2배
        case "chlorophyll":  return .weatherSpeedBoost(.sun, 2.0)
        case "swift-swim":   return .weatherSpeedBoost(.rain, 2.0)
        case "sand-rush":    return .weatherSpeedBoost(.sandstorm, 2.0)
        case "slush-rush":   return .weatherSpeedBoost(.snow, 2.0)

        // 날씨에서 능력치
        case "solar-power":  return .weatherStatBoost(.sun, .spAttack, 1.5)
        case "sand-force":   return .weatherStatBoost(.sandstorm, .attack, 1.3)

        // 날씨에서 회복
        case "ice-body":     return .weatherHeal(.snow, 16)
        case "rain-dish":    return .weatherHeal(.rain, 16)

        // 날씨에서 회피
        case "sand-veil":    return .weatherEvasion(.sandstorm)
        case "snow-cloak":   return .weatherEvasion(.snow)

        case "magic-guard":  return .magicGuard
        case "dry-skin":     return .dryskin

        // 접촉 시 상태이상
        case "static":       return .contactStatus(.paralysis, percent: 30)
        case "flame-body":   return .contactStatus(.burn, percent: 30)
        case "poison-point": return .contactStatus(.poison, percent: 30)
        case "effect-spore": return .contactStatus(.sleep, percent: 30)
        case "cute-charm":   return .contactStatus(.confusion, percent: 30)

        // 접촉 시 반사 피해
        case "rough-skin", "iron-barbs": return .contactDamage(8)

        // 기술 종류 강화
        case "iron-fist":    return .moveFlagBoost(.punch, 1.2)
        case "strong-jaw":   return .moveFlagBoost(.bite, 1.5)
        case "punk-rock":    return .moveFlagBoost(.sound, 1.3)
        case "tough-claws":  return .moveFlagBoost(.contact, 1.3)

        case "soundproof":   return .soundImmunity

        case "mold-breaker", "teravolt", "turboblaze": return .ignoreAbility
        case "battle-armor", "shell-armor":            return .criticalImmunity
        case "multiscale", "shadow-shield":            return .multiscale(0.5)

        // 타입 흡수
        case "water-absorb", "dry-skin-water": return .levitateLike(.water, 0.25)
        case "volt-absorb":                    return .levitateLike(.electric, 0.25)
        case "flash-fire":                     return .levitateLike(.fire, 0.0)
        case "sap-sipper":                     return .levitateLike(.grass, 0.0)
        case "motor-drive", "lightning-rod":   return .levitateLike(.electric, 0.0)
        case "storm-drain", "water-compaction-no": return .levitateLike(.water, 0.0)

        default:           return .none
        }
    }

    private static func localized(_ raw: Any?, _ lang: String) -> String? {
        guard let arr = raw as? [[String: Any]] else { return nil }
        for e in arr {
            guard let l = e["language"] as? [String: Any],
                  let n = l["name"] as? String, n == lang else { continue }
            if let v = e["name"] as? String { return v }
        }
        return nil
    }

    private static func shortEffect(_ raw: Any?) -> String {
        guard let arr = raw as? [[String: Any]] else { return "" }
        for e in arr {
            guard let l = e["language"] as? [String: Any],
                  let n = l["name"] as? String, n == "en" else { continue }
            if let v = e["short_effect"] as? String { return v }
        }
        return ""
    }

    func ability(_ slug: String) async -> AbilityDef? {
        if let a = abilities[slug] { return a }
        let url = cacheDir.appending(path: "ability-\(slug).json")
        var json: [String: Any]?
        if let d = try? Data(contentsOf: url) {
            json = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        } else {
            guard let u = URL(string: "https://pokeapi.co/api/v2/ability/\(slug)"),
                  let (data, _) = try? await session.data(from: u) else { return nil }
            try? data.write(to: url)
            json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        guard let j = json, let name = j["name"] as? String else { return nil }
        let def = AbilityDef(name: name,
                             koName: Self.localized(j["names"], "ko") ?? name,
                             shortEffect: Self.shortEffect(j["effect_entries"]),
                             kind: Self.kind(for: name))
        abilities[name] = def
        return def
    }

    /// 어떤 종이 가질 수 있는 특성들 (슬롯 순서, 숨겨진 특성 포함)
    func abilities(for sp: SpeciesDef) async -> [AbilityDef] {
        var out: [AbilityDef] = []
        for entry in sp.abilitySlots {
            if var a = await ability(entry.name) {
                a.isHidden = entry.hidden
                out.append(a)
            }
        }
        return out
    }
}
