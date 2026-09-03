import Foundation

/// 특성의 **배틀에서 실제로 작동하는** 효과.
///
/// PokeAPI 는 373개 특성을 이름·한글명·효과 텍스트로 주지만 효과는 산문이다.
/// 그래서 모든 특성을 **표시**는 하되, 아래에 구조화한 것만 **실제로 계산에 반영**한다.
/// (특성별 개별 구현이 필요하고, 날씨·접촉 판정처럼 이 엔진에 없는 개념에 의존하는 것도 많다)
enum AbilityKind: Codable, Hashable, Sendable, Equatable {
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

    // --- 확장 (2차) ---
    case statMultiplier(Stat, Double)           // 의욕(공격)/황금몸 등 상시 배율
    case statusSpeedBoost(Double)               // 속보 — 상태이상 시 스피드 상승
    case accuracyMultiplier(Double)             // 복안 — 명중률 상승
    case hustle                                 // 의욕 — 공격↑ 물리 명중↓
    case defeatist                              // 무기력 — HP 절반 이하에서 공격 반감
    case speedBoostEachTurn                     // 가속 — 턴마다 스피드 +1
    case boostOnKO(Stat, Int)                   // 자기과신/비스트부스트 — 쓰러뜨리면 상승
    case boostWhenHit(PType?, Stat, Int)        // 정의의마음/주눅/깨어진갑옷
    case boostOnFlinch(Stat, Int)               // 불굴의마음 — 풀죽으면 스피드 상승
    case contrary                               // 청개구리 — 능력 변화 반전
    case simple(Double)                         // 단순 — 능력 변화 2배
    case analytic(Double)                       // 애널라이즈 — 나중에 움직이면 강화
    case download                               // 다운로드 — 상대 방어 보고 공격/특공 상승
    case poisonHeal                             // 포이즌힐 — 독 피해 대신 회복
    case shedSkin(percent: Int)                 // 탈피 — 확률로 상태이상 회복
    case healInWeather(Weather)                 // 촉촉바디 — 비에서 상태이상 회복
    case noStatusInWeather(Weather)             // 리프가드 — 쾌청에서 상태이상 무효
    case earlyBird(Double)                      // 일찍기상 — 잠듦이 빨리 풀린다
    case statDropImmunity([Stat])               // 괴력집게/날카로운눈/큰부리
    case flinchImmunity                         // 정신력 — 풀죽지 않는다
    case wonderGuard                            // 불가사의부적 — 효과 굉장한 기술만 통한다
    case truant                                 // 게으름 — 한 턴 걸러 행동
    case priorityBoost(DamageClass?, Int)       // 짓궂은마음/질풍날개
    case pressure                               // 프레셔 — 상대 PP 추가 소모
    case damp                                   // 축축함 — 자폭 기술 봉쇄
    case aftermath(Int)                         // 유폭 — 쓰러질 때 접촉한 상대에게 피해
    case contactStatDrop(Stat, Int)             // 미끈미끈/엉겨붙는머리 — 접촉 시 상대 스피드↓
    case poisonTouch(percent: Int)              // 독수 — 접촉 공격 시 상대를 독으로
    case synchronize                            // 싱크로 — 받은 상태이상을 되돌려준다
    case absorbAndBoost(PType, Stat, Int)       // 초식/전기엔진 — 무효화 + 능력 상승
    case magicBounce                            // 매직미러 — 변화기를 되돌린다
    case unburden                               // 곡예 — 도구를 쓰면 스피드 2배
    case quickDraw(percent: Int)                // 선단 — 확률로 선공
    case moveTypeBoost([String], Double)        // 메가런처/칼날몸 — 특정 기술군 강화
    case healOnEntry                            // 재생력 — 물러날 때 회복 (교체·유턴에서 작동)
    case cureOnSwitch                           // 자연회복 — 물러나면 상태이상 회복

    // --- 확장 (3차) ---
    case gluttony                               // 먹보 — 열매를 HP 1/2 에서 먹는다
    case unnerve                                // 긴장감 — 상대가 열매를 먹지 못한다
    case liquidOoze                             // 해감액 — 흡수 기술이 오히려 피해를 준다
    case cursedBody(percent: Int)               // 저주받은바디 — 맞은 기술을 봉인
    case trace                                  // 트레이스 — 등장 시 상대 특성 복사
    case stickyHold                             // 점착 — 도구를 빼앗기지 않는다
    case pickup                                 // 픽업 — 소비된 도구를 주워온다
    case weightMultiplier(Double)               // 헤비메탈 / 라이트메탈

    /// 배틀 중 폼이 자동으로 바뀌는 특성 (날씨·HP 조건).
    /// 실제 처리는 FormChange.autoRule 이 하지만, 여기에 케이스가 없으면
    /// "표시만" 으로 잘못 표기된다.
    case autoFormChange

    /// 더블배틀 전용 — 1대1 에서는 발동할 수 없다 (미구현이 아니라 해당 없음)
    case doublesOnly
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
    var isImplemented: Bool { kind != .none && kind != .doublesOnly }
    /// 더블배틀 전용이라 1대1 에서는 애초에 발동할 수 없는가
    var isDoublesOnly: Bool { kind == .doublesOnly }
    /// UI 에 붙일 꼬리표
    var statusTag: String? {
        if isDoublesOnly { return "더블 전용" }
        if !isImplemented { return "표시만" }
        return nil
    }
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
        // 배틀 중 폼이 바뀌는 특성은 FormChange 가 처리한다.
        // 목록을 여기서 따로 적으면 규칙이 없는 특성까지 구현됐다고
        // 표시하게 되므로 반드시 그쪽 목록(autoAbilityNames)을 본다.
        if FormChange.isAutoAbility(slug) { return .autoFormChange }

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
        // --- 확장 매핑 ---
        case "compound-eyes":   return .accuracyMultiplier(1.3)
        case "victory-star":    return .accuracyMultiplier(1.1)
        case "hustle":          return .hustle
        case "defeatist":       return .defeatist
        case "speed-boost":     return .speedBoostEachTurn
        case "moxie", "chilling-neigh", "grim-neigh", "as-one-glastrier":
                                return .boostOnKO(.attack, 1)
        case "beast-boost":     return .boostOnKO(.attack, 1)
        case "soul-heart":      return .boostOnKO(.spAttack, 1)
        case "justified":       return .boostWhenHit(.dark, .attack, 1)
        case "rattled":         return .boostWhenHit(nil, .speed, 1)
        case "weak-armor":      return .boostWhenHit(nil, .speed, 2)
        case "steadfast":       return .boostOnFlinch(.speed, 1)
        case "contrary":        return .contrary
        case "simple":          return .simple(2.0)
        case "analytic":        return .analytic(1.3)
        case "download":        return .download
        case "poison-heal":     return .poisonHeal
        case "shed-skin":       return .shedSkin(percent: 33)
        case "hydration":       return .healInWeather(.rain)
        case "leaf-guard":      return .noStatusInWeather(.sun)
        case "early-bird":      return .earlyBird(2.0)
        case "hyper-cutter":    return .statDropImmunity([.attack])
        case "keen-eye", "illuminate", "mind-s-eye": return .statDropImmunity([])
        case "big-pecks":       return .statDropImmunity([.defense])
        case "inner-focus":     return .flinchImmunity
        case "wonder-guard":    return .wonderGuard
        case "truant":          return .truant
        case "prankster":       return .priorityBoost(.status, 1)
        case "gale-wings":      return .priorityBoost(nil, 1)
        case "triage":          return .priorityBoost(nil, 3)
        case "pressure":        return .pressure
        case "damp":            return .damp
        case "aftermath":       return .aftermath(4)
        case "gooey", "tangling-hair": return .contactStatDrop(.speed, 1)
        case "poison-touch":    return .poisonTouch(percent: 30)
        case "synchronize":     return .synchronize
        case "sap-sipper2":     return .absorbAndBoost(.grass, .attack, 1)
        case "motor-drive":     return .absorbAndBoost(.electric, .speed, 1)
        case "lightning-rod":   return .absorbAndBoost(.electric, .spAttack, 1)
        case "storm-drain":     return .absorbAndBoost(.water, .spAttack, 1)
        case "water-compaction":return .boostWhenHit(.water, .defense, 2)
        case "magic-bounce":    return .magicBounce
        case "unburden":        return .unburden
        case "quick-draw":      return .quickDraw(percent: 30)
        case "mega-launcher":   return .moveTypeBoost(["aura-sphere", "dark-pulse", "dragon-pulse",
                                                       "water-pulse", "heal-pulse", "origin-pulse",
                                                       "terrain-pulse"], 1.5)
        case "sharpness":       return .moveTypeBoost(["air-slash", "night-slash", "psycho-cut",
                                                       "slash", "cross-poison", "aerial-ace",
                                                       "leaf-blade", "sacred-sword", "razor-shell",
                                                       "solar-blade", "aqua-cutter", "kowtow-cleave"], 1.5)
        case "regenerator":     return .healOnEntry
        case "natural-cure":    return .cureOnSwitch
        case "quick-feet":      return .statusSpeedBoost(1.5)
        case "flare-boost":     return .statusAtkBoost(.spAttack, 1.5)
        case "toxic-boost":     return .statusAtkBoost(.attack, 1.5)
        case "overcoat":        return .powderImmunity
        case "sand-veil2":      return .weatherEvasion(.sandstorm)
        case "stall":           return .priorityBoost(nil, -1)
        case "vital-spirit2":   return .flinchImmunity
        case "oblivious", "own-tempo2": return .statusImmunity(.confusion)
        case "pure-power":      return .attackMultiplier(2.0)
        case "gorilla-tactics": return .statMultiplier(.attack, 1.5)
        case "transistor":      return .pinchBoost(.electric, 1.3)
        case "dragon-s-maw":    return .pinchBoost(.dragon, 1.5)
        case "rocky-payload":   return .pinchBoost(.rock, 1.5)
        case "steelworker", "steely-spirit": return .pinchBoost(.steel, 1.5)

        case "serene-grace": return .sereneGrace(2.0)
        case "shield-dust": return .shieldDust

        // --- 확장 (3차) ---
        case "gluttony":       return .gluttony
        case "unnerve", "as-one-spectrier": return .unnerve
        case "liquid-ooze":    return .liquidOoze
        case "cursed-body":    return .cursedBody(percent: 30)
        case "trace":          return .trace
        case "sticky-hold":    return .stickyHold
        case "pickup":         return .pickup
        case "heavy-metal":    return .weightMultiplier(2.0)
        case "light-metal":    return .weightMultiplier(0.5)

        // 더블배틀 전용 — 아군이 없으면 발동 자체가 불가능하다
        case "telepathy", "friend-guard", "healer", "symbiosis", "battery",
             "power-spot", "steely-spirit2", "victory-star2", "plus", "minus",
             "sweet-veil", "flower-veil", "aroma-veil", "storm-drain2", "commander":
            return .doublesOnly

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
