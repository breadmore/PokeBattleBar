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

    struct StatChange: Codable, Hashable, Sendable {
        var stat: Stat
        var change: Int
    }

    var display: String { koName.isEmpty ? name : koName }
}

/// 종 정의 — 종족값·타입·배울 수 있는 기술 목록
struct SpeciesDef: Codable, Sendable {
    var id: Int
    var name: String
    var koName: String
    var types: [PType]
    var baseStats: [Stat: Int]
    var learnableMoves: [String]     // 기술 이름 (PokeAPI slug)

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

        let def = SpeciesDef(
            id: id,
            name: poke["name"] as? String ?? "#\(id)",
            koName: koName,
            types: types.isEmpty ? [.normal] : types,
            baseStats: stats,
            learnableMoves: learnable
        )
        species[id] = def
        return def
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

        let ailmentName = ((meta["ailment"] as? [String: Any])?["name"] as? String) ?? "none"
        let ailment = Ailment(apiName: ailmentName)
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
            ailment: ailment,
            ailmentChance: ailmentChance,
            statChanges: changes,
            statChangeChance: statChance,
            minHits: meta["min_hits"] as? Int,
            maxHits: meta["max_hits"] as? Int,
            drainPercent: meta["drain"] as? Int ?? 0,
            healingPercent: meta["healing"] as? Int ?? 0,
            flinchChance: meta["flinch_chance"] as? Int ?? 0,
            critRateBonus: meta["crit_rate"] as? Int ?? 0
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
