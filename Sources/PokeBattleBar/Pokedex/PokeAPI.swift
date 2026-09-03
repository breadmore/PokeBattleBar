import Foundation

// MARK: - 도메인 모델

enum PType: String, Codable, CaseIterable, Sendable {
    case normal, fighting, flying, poison, ground, rock, bug, ghost, steel
    case fire, water, grass, electric, psychic, ice, dragon, dark, fairy

    var ko: String {
        switch self {
        case .normal: "노말"; case .fighting: "격투"; case .flying: "비행"
        case .poison: "독";   case .ground: "땅";    case .rock: "바위"
        case .bug: "벌레";    case .ghost: "고스트"; case .steel: "강철"
        case .fire: "불꽃";   case .water: "물";     case .grass: "풀"
        case .electric: "전기"; case .psychic: "에스퍼"; case .ice: "얼음"
        case .dragon: "드래곤"; case .dark: "악";     case .fairy: "페어리"
        }
    }
}

enum DamageClass: String, Codable, Sendable { case physical, special, status }

enum Ailment: String, Codable, Sendable {
    case none, paralysis, sleep, freeze, burn, poison, toxic, confusion, flinch, unknown

    init(apiName: String) {
        switch apiName {
        case "none", "": self = .none
        case "paralysis": self = .paralysis
        case "sleep": self = .sleep
        case "freeze": self = .freeze
        case "burn": self = .burn
        case "poison": self = .poison
        case "toxic": self = .toxic
        case "confusion": self = .confusion
        default: self = .unknown       // 미구현 부가효과는 무시된다
        }
    }
    var ko: String {
        switch self {
        case .paralysis: "마비"; case .sleep: "잠듦"; case .freeze: "얼음"
        case .burn: "화상"; case .poison: "독"; case .toxic: "맹독"
        case .confusion: "혼란"; default: "-"
        }
    }
}

/// 기술 정의 — PokeAPI /move/{name} 에서 뽑아온다.
struct MoveDef: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var koName: String
    var type: PType
    var damageClass: DamageClass
    var power: Int?
    var accuracy: Int?          // nil = 반드시 명중
    var pp: Int
    var priority: Int
    var targetsSelf: Bool       // stat_changes 를 자신에게 적용하는지
    /// PokeAPI 의 target 원문. 타입 면역을 변화기에 적용할 때
    /// "상대를 노리는 기술" 과 "필드에 걸리는 기술" 을 구분해야 한다.
    var target: String = "selected-pokemon"
    var ailment: Ailment
    var ailmentChance: Int      // 0 = 부가효과 없음 / 100 = 확정
    var statChanges: [StatChange]
    var statChangeChance: Int
    var minHits: Int?
    var maxHits: Int?
    var drainPercent: Int       // >0 흡수, <0 반동
    var healingPercent: Int
    var flinchChance: Int
    var critRateBonus: Int
    /// 공격 판정보다 먼저 쓰러지는가 (대폭발 계열).
    var selfKOBeforeMove: Bool { MoveFlags.selfDestructsBeforeMove(name) }

    /// 쓴 쪽이 쓰러지는 기술 (대폭발·자폭·목숨걸기 등).
    /// PokeAPI 의 구조화된 필드에는 이 정보가 **없다** — effect 텍스트에만 "User faints." 로 있다.
    var selfKO: Bool
    /// 위력 대신 별도 규칙으로 데미지를 정하는 기술
    var specialDamage: SpecialDamage
    /// PokeAPI 의 영문 short_effect — UI 툴팁과 미구현 판정에 쓴다
    var shortEffect: String
    /// 묶기 기술(바다회오리·회오리불꽃 등) 의 지속 턴수. 없으면 nil.
    /// PokeAPI 는 ailment="trap" 과 min/max_turns 로 준다.
    var trapTurns: ClosedRange<Int>?
    /// 쓴 뒤 자신이 교체되는 기술 (유턴·볼트체인지·퀵턴).
    /// PokeAPI 는 이걸 구조화해 주지 않아 이름으로 판정한다.
    var isPivot: Bool = false

    struct StatChange: Codable, Hashable, Sendable {
        var stat: Stat
        var change: Int
    }

    var display: String { koName.isEmpty ? name : koName }

    /// 상대 포켓몬을 직접 노리는 기술인가.
    /// 날씨·필드 기술(쾌청=불꽃, 일렉트릭필드=전기) 은 상대를 노리지 않으므로
    /// 타입 면역으로 막혀선 안 된다.
    var targetsOpponent: Bool {
        switch target {
        case "selected-pokemon", "random-opponent", "all-opponents", "all-other-pokemon":
            return true
        default:
            return false
        }
    }

    /// 데미지를 주는 기술인가.
    /// 위력이 있거나, 특수 데미지 규칙이 있거나, 무게로 위력이 정해지는 기술이면 공격기다.
    var isDamaging: Bool {
        if (power ?? 0) > 0 { return true }
        if specialDamage != .none { return true }
        if BattleEngine.weightBasedPower(move: name, attackerWeight: 1, targetWeight: 1) != nil {
            return true
        }
        return false
    }
}

/// 종이 가질 수 있는 특성 한 칸
struct AbilitySlot: Codable, Hashable, Sendable {
    var name: String
    var slot: Int
    var hidden: Bool
}

/// 메가 / 거다이맥스 폼의 종족값과 타입
struct FormStats: Codable, Sendable {
    var name: String
    var types: [PType]
    var baseStats: [Stat: Int]
    func base(_ s: Stat) -> Int { baseStats[s] ?? 1 }

    /// "charizard-mega-x" → "메가 X", "snorlax-gmax" → "거다이맥스"
    var suffixLabel: String {
        if name.hasSuffix("-gmax") { return "거다이맥스" }
        if name.hasSuffix("-mega-x") { return "메가 X" }
        if name.hasSuffix("-mega-y") { return "메가 Y" }
        if name.contains("-mega") { return "메가" }
        return name
    }
}

/// 위력 공식을 따르지 않는 데미지 규칙
enum SpecialDamage: Codable, Hashable, Sendable {
    case none
    case userCurrentHP        // 목숨걸기 — 쓴 쪽의 현재 HP 만큼
    case userLevel            // 나이트헤드 / 지구던지기 — 레벨만큼
    case fixed(Int)           // 용의분노 40 / 소닉붐 20
}

/// 종 정의 — 종족값·타입·배울 수 있는 기술 목록
struct SpeciesDef: Codable, Sendable {
    var id: Int
    var name: String
    var koName: String
    var types: [PType]
    var baseStats: [Stat: Int]
    var learnableMoves: [String]     // 기술 이름 (PokeAPI slug)
    /// 메가진화 폼 이름 (리자몽처럼 X/Y 두 개일 수 있다). 없으면 메가진화 불가.
    var megaForms: [String] = []
    /// 거다이맥스 폼 이름. 없으면 거다이맥스 불가.
    var gmaxForm: String? = nil
    /// 이 종이 가질 수 있는 특성 (슬롯 순서, 숨겨진 특성 포함)
    var abilitySlots: [AbilitySlot] = []
    /// 무게 (헥토그램). 헤비메탈·저울짓기·헤비봄버 계산에 쓴다.
    var weight: Int = 0

    var canMega: Bool { !megaForms.isEmpty }
    /// 거다이맥스 전용 폼이 있는가 (다이맥스는 종족 제한이 없다)
    var canGigantamax: Bool { gmaxForm != nil }

    var display: String { koName.isEmpty ? name : koName }
    func base(_ s: Stat) -> Int { baseStats[s] ?? 1 }
}

// MARK: - 캐시된 PokeAPI 클라이언트

actor PokeAPI {
    static let shared = PokeAPI()

    private let session: URLSession
    private let cacheDir: URL
    private var species: [Int: SpeciesDef] = [:]
    private var moves: [String: MoveDef] = [:]
    private var forms: [String: FormStats] = [:]
    private var chart: TypeChart?

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
        cacheDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/PokeBattleBar/pokeapi")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: 디스크 캐시

    private func cacheURL(_ key: String) -> URL {
        cacheDir.appending(path: key.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    private func cachedRaw(_ key: String) -> Data? {
        try? Data(contentsOf: cacheURL(key))
    }

    private func fetchRaw(_ path: String, cacheKey: String) async throws -> Data {
        if let d = cachedRaw(cacheKey) { return d }
        guard let url = URL(string: "https://pokeapi.co/api/v2/\(path)") else {
            throw PokeAPIError.badURL(path)
        }
        let (data, resp) = try await session.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw PokeAPIError.http(http.statusCode, path)
        }
        try? data.write(to: cacheURL(cacheKey))
        return data
    }

    // MARK: 종

    func species(_ id: Int) async throws -> SpeciesDef {
        if let s = species[id] { return s }

        let pokeData = try await fetchRaw("pokemon/\(id)", cacheKey: "pokemon-\(id)")
        let poke = try JSONSerialization.jsonObject(with: pokeData) as? [String: Any] ?? [:]

        let speciesData = try await fetchRaw("pokemon-species/\(id)", cacheKey: "species-\(id)")
        let sp = try JSONSerialization.jsonObject(with: speciesData) as? [String: Any] ?? [:]

        var types: [PType] = []
        if let ts = poke["types"] as? [[String: Any]] {
            let ordered = ts.sorted { ($0["slot"] as? Int ?? 0) < ($1["slot"] as? Int ?? 0) }
            types = ordered.compactMap {
                guard let t = $0["type"] as? [String: Any], let n = t["name"] as? String else { return nil }
                return PType(rawValue: n)
            }
        }

        var stats: [Stat: Int] = [:]
        if let ss = poke["stats"] as? [[String: Any]] {
            for entry in ss {
                guard let st = entry["stat"] as? [String: Any],
                      let n = st["name"] as? String,
                      let s = Stat(apiName: n),
                      let v = entry["base_stat"] as? Int else { continue }
                stats[s] = v
            }
        }

        // 배울 수 있는 기술 전부 (버전 무관). 랜덤 4개를 여기서 뽑는다.
        var learnable: [String] = []
        if let ms = poke["moves"] as? [[String: Any]] {
            for m in ms {
                guard let mv = m["move"] as? [String: Any], let n = mv["name"] as? String else { continue }
                learnable.append(n)
            }
        }

        let koName = Self.localizedName(sp["names"], lang: "ko")
            ?? (poke["name"] as? String ?? "#\(id)")

        // 특성 슬롯 — PokeAPI 가 슬롯 번호와 숨겨진 특성 여부를 준다
        var abilitySlots: [AbilitySlot] = []
        if let abs = poke["abilities"] as? [[String: Any]] {
            for a in abs {
                guard let ab = a["ability"] as? [String: Any],
                      let n = ab["name"] as? String else { continue }
                abilitySlots.append(AbilitySlot(name: n,
                                                slot: a["slot"] as? Int ?? 0,
                                                hidden: a["is_hidden"] as? Bool ?? false))
            }
            abilitySlots.sort { $0.slot < $1.slot }
        }

        // 메가 / 거다이맥스 폼은 species 의 varieties 에 별도 pokemon 으로 들어 있다
        var megaForms: [String] = []
        var gmaxForm: String?
        if let vs = sp["varieties"] as? [[String: Any]] {
            for v in vs {
                guard let p = v["pokemon"] as? [String: Any],
                      let n = p["name"] as? String else { continue }
                if n.contains("-mega") { megaForms.append(n) }
                if n.hasSuffix("-gmax") { gmaxForm = n }
            }
        }

        let def = SpeciesDef(
            id: id,
            name: poke["name"] as? String ?? "#\(id)",
            koName: koName,
            types: types.isEmpty ? [.normal] : types,
            baseStats: stats,
            learnableMoves: learnable,
            megaForms: megaForms.sorted(),
            gmaxForm: gmaxForm,
            abilitySlots: abilitySlots,
            weight: poke["weight"] as? Int ?? 0
        )
        species[id] = def
        return def
    }

    /// 폼(메가·거다이맥스) 의 종족값과 타입. `pokemon/{name}` 으로 받는다.
    func form(named name: String) async throws -> FormStats {
        if let f = forms[name] { return f }
        let data = try await fetchRaw("pokemon/\(name)", cacheKey: "pokemon-\(name)")
        let poke = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        var types: [PType] = []
        if let ts = poke["types"] as? [[String: Any]] {
            let ordered = ts.sorted { ($0["slot"] as? Int ?? 0) < ($1["slot"] as? Int ?? 0) }
            types = ordered.compactMap {
                guard let t = $0["type"] as? [String: Any], let n = t["name"] as? String else { return nil }
                return PType(rawValue: n)
            }
        }
        var stats: [Stat: Int] = [:]
        if let ss = poke["stats"] as? [[String: Any]] {
            for entry in ss {
                guard let st = entry["stat"] as? [String: Any],
                      let n = st["name"] as? String,
                      let s = Stat(apiName: n),
                      let v = entry["base_stat"] as? Int else { continue }
                stats[s] = v
            }
        }
        // 폼 이름의 한글명은 species 쪽에 없으므로 접미사로 표시명을 만든다
        let f = FormStats(name: name,
                          types: types.isEmpty ? [.normal] : types,
                          baseStats: stats)
        forms[name] = f
        return f
    }

    // MARK: 기술

    func move(_ name: String) async throws -> MoveDef {
        if let m = moves[name] { return m }
        let data = try await fetchRaw("move/\(name)", cacheKey: "move-\(name)")
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let typeName = ((j["type"] as? [String: Any])?["name"] as? String) ?? "normal"
        let dcName = ((j["damage_class"] as? [String: Any])?["name"] as? String) ?? "status"
        let targetName = ((j["target"] as? [String: Any])?["name"] as? String) ?? "selected-pokemon"
        let meta = j["meta"] as? [String: Any] ?? [:]
        let effectChance = j["effect_chance"] as? Int

        var changes: [MoveDef.StatChange] = []
        if let sc = j["stat_changes"] as? [[String: Any]] {
            for c in sc {
                guard let st = c["stat"] as? [String: Any],
                      let n = st["name"] as? String,
                      let s = Stat(apiName: n),
                      let ch = c["change"] as? Int, ch != 0 else { continue }
                changes.append(.init(stat: s, change: ch))
            }
        }

        // PokeAPI 는 자폭을 구조화해서 주지 않는다. 영문 effect 텍스트와 명시 목록을 함께 본다.
        let shortEffect = Self.shortEffect(j["effect_entries"])
        // 자폭 판정은 Showdown 의 selfdestruct 를 1순위로 쓴다.
        // PokeAPI 는 이 정보를 구조화해 주지 않아 예전엔 수기 목록 + 텍스트 매칭이었다.
        let selfKO = MoveFlags.isSelfDestruct(name)
            || Self.selfKOMoves.contains(name)
            || shortEffect.lowercased().contains("user faints")
        let specialDamage = Self.specialDamage(for: name)

        // 묶기 기술 — ailment 가 "trap" 이면 min/max_turns 동안 지속 피해를 준다
        var trapTurns: ClosedRange<Int>?
        if ((meta["ailment"] as? [String: Any])?["name"] as? String) == "trap",
           let lo = meta["min_turns"] as? Int, let hi = meta["max_turns"] as? Int, lo > 0 {
            trapTurns = lo...max(lo, hi)
        }

        let ailmentName = ((meta["ailment"] as? [String: Any])?["name"] as? String) ?? "none"
        var ailment = Ailment(apiName: ailmentName)
        // PokeAPI 에는 "맹독" 상태가 따로 없다 — 맹독도 ailment 가 "poison" 으로 온다.
        // 그대로 두면 턴마다 누적되는 맹독이 고정 1/8 짜리 일반 독으로 걸린다.
        if Self.badlyPoisonMoves.contains(name) { ailment = .toxic }
        // PokeAPI 는 확정 효과를 chance 0 으로 표기한다 — 상태기는 확정으로 본다.
        var ailmentChance = meta["ailment_chance"] as? Int ?? 0
        if ailment != .none, ailmentChance == 0 {
            ailmentChance = (dcName == "status") ? 100 : (effectChance ?? 100)
        }

        var statChance = effectChance ?? 0
        if !changes.isEmpty, statChance == 0 { statChance = 100 }

        let def = MoveDef(
            name: name,
            koName: Self.localizedName(j["names"], lang: "ko") ?? name,
            type: PType(rawValue: typeName) ?? .normal,
            damageClass: DamageClass(rawValue: dcName) ?? .status,
            power: j["power"] as? Int,
            accuracy: j["accuracy"] as? Int,
            pp: j["pp"] as? Int ?? 10,
            priority: j["priority"] as? Int ?? 0,
            targetsSelf: targetName == "user" || targetName == "users-field" || targetName == "user-and-allies",
            target: targetName,
            ailment: ailment,
            ailmentChance: ailmentChance,
            statChanges: changes,
            statChangeChance: statChance,
            minHits: meta["min_hits"] as? Int,
            maxHits: meta["max_hits"] as? Int,
            drainPercent: meta["drain"] as? Int ?? 0,
            healingPercent: meta["healing"] as? Int ?? 0,
            flinchChance: meta["flinch_chance"] as? Int ?? 0,
            critRateBonus: meta["crit_rate"] as? Int ?? 0,
            selfKO: selfKO,
            specialDamage: specialDamage,
            shortEffect: shortEffect,
            trapTurns: trapTurns,
            isPivot: MoveFlags.isSelfSwitch(name) || Self.pivotMoves.contains(name)
        )
        moves[name] = def
        return def
    }

    // MARK: 상성표

    func typeChart() async throws -> TypeChart {
        if let c = chart { return c }
        var table: [PType: [PType: Double]] = [:]
        for t in PType.allCases {
            let data = try await fetchRaw("type/\(t.rawValue)", cacheKey: "type-\(t.rawValue)")
            let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let rel = j["damage_relations"] as? [String: Any] ?? [:]
            var row: [PType: Double] = [:]
            func apply(_ key: String, _ mult: Double) {
                guard let arr = rel[key] as? [[String: Any]] else { return }
                for e in arr {
                    if let n = e["name"] as? String, let d = PType(rawValue: n) { row[d] = mult }
                }
            }
            apply("double_damage_to", 2.0)
            apply("half_damage_to", 0.5)
            apply("no_damage_to", 0.0)
            table[t] = row
        }
        let c = TypeChart(table: table)
        chart = c
        return c
    }

    // MARK: 유틸

    /// 쓴 뒤 자신이 교체되는 기술.
    /// PokeAPI 는 "User must switch out after attacking" 을 텍스트로만 주므로 목록으로 둔다.
    static let pivotMoves: Set<String> = [
        "u-turn", "volt-switch", "flip-turn", "parting-shot", "baton-pass",
        "chilly-reception", "shed-tail"
    ]

    /// 맹독(누적 증가) 을 거는 기술. PokeAPI 는 일반 독과 구분해주지 않는다.
    static let badlyPoisonMoves: Set<String> = ["toxic", "poison-fang"]

    /// 쓴 쪽이 쓰러지는 기술. effect 텍스트만으로는 놓치는 경우가 있어 목록을 함께 둔다.
    static let selfKOMoves: Set<String> = [
        "explosion", "self-destruct", "misty-explosion",
        "final-gambit", "memento", "healing-wish", "lunar-dance"
    ]

    private static func specialDamage(for name: String) -> SpecialDamage {
        switch name {
        case "final-gambit":                 return .userCurrentHP
        case "night-shade", "seismic-toss":  return .userLevel
        case "dragon-rage":                  return .fixed(40)
        case "sonic-boom":                   return .fixed(20)
        default:                             return .none
        }
    }

    private static func shortEffect(_ raw: Any?) -> String {
        guard let arr = raw as? [[String: Any]] else { return "" }
        for e in arr {
            guard let l = e["language"] as? [String: Any],
                  let ln = l["name"] as? String, ln == "en" else { continue }
            if let t = e["short_effect"] as? String { return t }
        }
        return ""
    }

    private static func localizedName(_ raw: Any?, lang: String) -> String? {
        guard let arr = raw as? [[String: Any]] else { return nil }
        for e in arr {
            guard let l = e["language"] as? [String: Any],
                  let ln = l["name"] as? String, ln == lang,
                  let n = e["name"] as? String else { continue }
            return n
        }
        return nil
    }
}

enum PokeAPIError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case .badURL(let p): "잘못된 PokeAPI 경로: \(p)"
        case .http(let c, let p): "PokeAPI \(p) 응답 \(c)"
        }
    }
}
