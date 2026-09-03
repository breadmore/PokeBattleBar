import Foundation

/// 지닌 도구의 **배틀에서 실제로 작동하는** 효과.
/// PokeAPI 는 효과를 산문으로만 주므로(`short_effect`), 구조화는 여기서 한다.
enum ItemKind: Codable, Hashable, Sendable {
    case none                                   // 배틀 효과 없음 (표시만)

    // 변신 자격 도구
    case megaStone(form: String)                // 특정 메가 폼으로 진화 허용
    case zCrystalType(PType)                    // 해당 타입 Z기술 허용
    case zCrystalSignature(species: Int)        // 전용 Z기술 (특정 종만)
    case dynamaxBand                            // 다이맥스 허용
    case maxMushroom                            // 거다이맥스 허용

    // 상시 효과
    case choice(stat: Stat)                     // 구애 계열 — 스탯 1.5배, 기술 고정
    case lifeOrb                                // 데미지 1.3배, 최대HP 10% 반동
    case focusSash                              // 풀피에서 일격 방지 (1회)
    case leftovers                              // 턴마다 최대HP 1/16 회복
    case expertBelt                             // 효과 굉장한 기술 1.2배
    case classBoost(DamageClass, Double)        // 파워리스트/지식안경 — 물리/특수 강화
    case typePlate(PType, Double)               // 플레이트 — 해당 타입 강화
    case eviolite                               // 미진화 방어·특방 1.5배
    case assaultVest                            // 특방 1.5배, 변화기 사용 불가
    case selfStatusOrb(Ailment)                 // 화염구슬/독구슬 — 턴 종료 시 자신에게
    case quickClaw(numerator: Int, denominator: Int)  // 확률 선공 (원작 3/16)
}

/// 도구 정의. 이름·한글명·효과 텍스트는 PokeAPI 에서 실제로 받아온다.
struct ItemDef: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var koName: String
    var category: String
    var shortEffect: String
    var kind: ItemKind

    var display: String { koName.isEmpty ? name : koName }

    /// 변신 자격을 주는 도구인가
    var isTransformItem: Bool {
        switch kind {
        case .megaStone, .zCrystalType, .zCrystalSignature, .dynamaxBand, .maxMushroom: true
        default: false
        }
    }

    /// UI 분류
    var group: String {
        switch kind {
        case .megaStone:                        "메가스톤"
        case .zCrystalType, .zCrystalSignature: "Z크리스탈"
        case .dynamaxBand, .maxMushroom:        "다이맥스"
        case .none:                             "기타"
        default:                                "배틀 도구"
        }
    }
}

/// PokeAPI 에서 도구를 받아 배틀 효과로 매핑한다.
actor ItemCatalog {
    static let shared = ItemCatalog()

    private var loaded = false
    private(set) var items: [String: ItemDef] = [:]

    /// 배틀에 의미가 있는 도구만 받는다 — 2223개를 전부 받을 이유가 없다.
    private static let battleItems: [String] = [
        "leftovers", "life-orb", "focus-sash", "expert-belt",
        "muscle-band", "wise-glasses", "choice-band", "choice-specs", "choice-scarf",
        "eviolite", "assault-vest", "flame-orb", "toxic-orb", "quick-claw",
        "dynamax-band", "max-mushrooms"
    ]

    /// 타입 Z크리스탈 접두사 → 타입. 불규칙한 것들이 있어 표로 둔다.
    private static let zPrefix: [String: PType] = [
        "normalium": .normal,   "firium": .fire,        "waterium": .water,
        "electrium": .electric, "grassium": .grass,     "icium": .ice,
        "fightinium": .fighting,"poisonium": .poison,   "groundium": .ground,
        "flyinium": .flying,    "psychium": .psychic,   "buginium": .bug,
        "rockium": .rock,       "ghostium": .ghost,     "dragonium": .dragon,
        "darkinium": .dark,     "steelium": .steel,     "fairium": .fairy
    ]

    /// 전용 Z크리스탈 → 그 종만 쓸 수 있다.
    /// PokeAPI 는 어느 종의 것인지 구조화해서 주지 않아 표로 둔다.
    static let signatureZ: [String: Int] = [
        "pikanium": 25,      // 피카츄 — 캐터스트로피카
        "pikashunium": 25,   // 피카츄(모자) — 1000만볼트
        "aloraichium": 26,   // 알로라 라이츄 — 라이츄서핑
        "eevium": 133,       // 이브이 — 나인에볼브스트
        "snorlium": 143,     // 잠만보 — 절대엎어치기
        "mewnium": 151,      // 뮤 — 게노시스슈퍼노바
        "decidium": 724,     // 모크나이퍼 — 슈터스타애로
        "incinium": 727,     // 어흥염 — 불꽃의헤비급라리아트
        "primarium": 730,    // 누리레느 — 오케스트라
        "marshadium": 802,   // 마샤도 — 확산일격
        "tapunium": 785      // 카푸꼬꼬꼭 — 수호신의일격
    ]

    private static let plates: [String: PType] = [
        "flame-plate": .fire,    "splash-plate": .water,   "zap-plate": .electric,
        "meadow-plate": .grass,  "icicle-plate": .ice,     "fist-plate": .fighting,
        "toxic-plate": .poison,  "earth-plate": .ground,   "sky-plate": .flying,
        "mind-plate": .psychic,  "insect-plate": .bug,     "stone-plate": .rock,
        "spooky-plate": .ghost,  "draco-plate": .dragon,   "dread-plate": .dark,
        "iron-plate": .steel,    "pixie-plate": .fairy
    ]

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

    private func fetch(_ path: String, key: String) async throws -> [String: Any] {
        let url = cacheDir.appending(path: key + ".json")
        if let d = try? Data(contentsOf: url) {
            return try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
        }
        guard let u = URL(string: "https://pokeapi.co/api/v2/\(path)") else { return [:] }
        let (data, _) = try await session.data(from: u)
        try? data.write(to: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
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

    /// 도구 하나를 받아 배틀 효과를 붙인다.
    private func load(_ name: String) async -> ItemDef? {
        guard let j = try? await fetch("item/\(name)", key: "item-\(name)") else { return nil }
        guard let slug = j["name"] as? String else { return nil }
        let ko = Self.localized(j["names"], "ko") ?? slug
        let eff = Self.shortEffect(j["effect_entries"])
        let cat = ((j["category"] as? [String: Any])?["name"] as? String) ?? ""
        return ItemDef(name: slug, koName: ko, category: cat, shortEffect: eff,
                       kind: Self.kind(for: slug, category: cat, effect: eff))
    }

    /// 도구 이름·카테고리·효과 텍스트로 구조화된 효과를 결정한다.
    static func kind(for slug: String, category: String, effect: String) -> ItemKind {
        // 메가스톤: "Allows Charizard to Mega Evolve into Mega Charizard X."
        if category == "mega-stones" {
            if let form = megaForm(fromEffect: effect) { return .megaStone(form: form) }
            return .none
        }
        // Z크리스탈
        if category == "z-crystals" {
            let base = slug.replacingOccurrences(of: "-z--held", with: "")
                           .replacingOccurrences(of: "-z", with: "")
            if let t = zPrefix[base] { return .zCrystalType(t) }
            if let sid = signatureZ[base] { return .zCrystalSignature(species: sid) }
            return .none
        }
        if let t = plates[slug] { return .typePlate(t, 1.2) }

        switch slug {
        case "dynamax-band":  return .dynamaxBand
        case "max-mushrooms": return .maxMushroom
        case "leftovers":     return .leftovers
        case "life-orb":      return .lifeOrb
        case "focus-sash":    return .focusSash
        case "expert-belt":   return .expertBelt
        case "muscle-band":   return .classBoost(.physical, 1.1)
        case "wise-glasses":  return .classBoost(.special, 1.1)
        case "choice-band":   return .choice(stat: .attack)
        case "choice-specs":  return .choice(stat: .spAttack)
        case "choice-scarf":  return .choice(stat: .speed)
        case "eviolite":      return .eviolite
        case "assault-vest":  return .assaultVest
        case "flame-orb":     return .selfStatusOrb(.burn)
        case "toxic-orb":     return .selfStatusOrb(.toxic)
        case "quick-claw":    return .quickClaw(numerator: 3, denominator: 16)
        default:              return .none
        }
    }

    /// "Mega Charizard X" → "charizard-mega-x"
    static func megaForm(fromEffect effect: String) -> String? {
        guard let r = effect.range(of: "Mega Evolve into Mega ") else { return nil }
        var tail = String(effect[r.upperBound...])
        if let dot = tail.firstIndex(of: ".") { tail = String(tail[..<dot]) }
        let parts = tail.split(separator: " ").map(String.init)
        guard let species = parts.first?.lowercased() else { return nil }
        if parts.count >= 2 {
            let suffix = parts[1].lowercased()
            if suffix == "x" || suffix == "y" { return "\(species)-mega-\(suffix)" }
        }
        return "\(species)-mega"
    }

    // MARK: 적재

    /// 배틀 도구 + 메가스톤 + Z크리스탈 + 플레이트를 받아둔다.
    func loadAll() async {
        guard !loaded else { return }
        var out: [String: ItemDef] = [:]

        // 카테고리로 한 번에 목록을 받는다
        var names = Set(Self.battleItems)
        names.formUnion(Self.plates.keys)
        for cat in ["mega-stones", "z-crystals"] {
            if let j = try? await fetch("item-category/\(cat)", key: "itemcat-\(cat)"),
               let arr = j["items"] as? [[String: Any]] {
                for i in arr { if let n = i["name"] as? String { names.insert(n) } }
            }
        }

        for n in names {
            if let d = await load(n) { out[d.name] = d }
        }
        items = out
        loaded = true
    }

    func item(_ name: String) -> ItemDef? { items[name] }

    /// 어떤 개체가 지닐 수 있는 도구 목록 (그 종에게 의미 있는 것만 위로).
    /// 메가스톤은 자기 종 것만, 전용 Z크리스탈은 제외한다.
    func available(forSpecies sp: SpeciesDef) -> [ItemDef] {
        items.values.filter { d in
            switch d.kind {
            case .megaStone(let form):
                return sp.megaForms.contains(form)
            case .zCrystalSignature(let sid):
                return sid == sp.id                // 전용 Z 는 그 종에게만
            case .maxMushroom:
                return sp.canGigantamax            // 거다이맥스 폼이 없으면 의미 없다
            case .none:
                return false                       // 배틀 효과 없는 도구는 숨긴다
            default:
                return true
            }
        }
        .sorted { ($0.group, $0.display) < ($1.group, $1.display) }
    }
}

/// 끼운 도구가 그 개체에게 실제로 작동하는지
struct ItemReadiness: Sendable {
    var ok: Bool
    var headline: String     // "메가진화 가능" / "거다이맥스 불가"
    var detail: String       // 이유 또는 부연
}

/// 로비 장비 경고
struct LoadoutWarning: Identifiable, Sendable {
    enum Severity: Sendable { case redundant, waste }
    var id: String
    var severity: Severity
    var title: String
    var detail: String
}
