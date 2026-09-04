import Foundation

/// Pokémon Showdown 배틀 데이터.
///
/// PokeAPI 는 한글명·스프라이트·종족값을 주지만 **배틀 로직 플래그를 주지 않는다.**
/// 접촉 여부, 자기 교체(유턴), 자폭, 방어 관통, 손가락흔들기 대상, G-Max 기술 —
/// 전부 지금까지 손으로 표를 써서 관리하던 것들이고, 빠뜨리면 조용히 버그가 된다.
/// Showdown(MIT) 이 이걸 954개 기술에 대해 구조화해 두었으므로 그대로 가져다 쓴다.
struct ShowdownMove: Sendable {
    var flags: Set<String> = []
    var basePower: Int?
    var type: String?
    var category: String?
    var selfSwitch: Bool = false
    /// Showdown 의 selfdestruct 값.
    /// "always" = 대폭발 계열, 빗나가거나 무효여도 **공격보다 먼저** 쓰러진다.
    /// "ifHit"  = 목숨걸기·메멘토 계열, 효과를 낸 **뒤에** 쓰러진다.
    var selfDestructMode: String?
    var selfDestruct: Bool { selfDestructMode != nil }
    var selfDestructBeforeMove: Bool { selfDestructMode == "always" }
    var isMax: Bool = false
    var isZ: Bool = false
    var nonstandard: String?
    var multiHitMin: Int?
    var multiHitMax: Int?
    /// 반동 / 흡수 / 회복 비율 ([분자, 분모])
    var recoil: [Int]?
    var drain: [Int]?
    var heal: [Int]?
    /// 상대 / 자신 능력치 변화
    var boosts: [String: Int]?
    var selfBoosts: [String: Int]?
    var critRatio: Int?
    var ohko: Bool = false
    var forceSwitch: Bool = false
    var volatileStatus: String?
    var status: String?
    /// Showdown 이 코드로만 표현한 효과가 있는 기술 (우리가 완전히 재현하지 못할 수 있다)
    var hasCustomCode: Bool = false
    /// 자신에게 걸리는 상태 — 파괴광선의 mustrecharge 가 여기 온다
    var selfVolatile: String?
    var selfStatus: String?
    /// 모으는 턴 동안 몸을 숨긴다 (땅속·공중·물속). 그 동안 대부분의 기술이 맞지 않는다.
    var hidesUser: Bool = false
    var target: String?

    /// 솔라빔처럼 **모으는 턴**이 있는 2턴 기술
    var isCharge: Bool { flags.contains("charge") }
    /// 난동부리기처럼 **여러 턴 동안 조작할 수 없는** 기술
    var locksUser: Bool { selfVolatile == "lockedmove" || volatileStatus == "lockedmove" }
    /// 데구르르처럼 연속으로 굴러가는 기술
    var rollsOn: Bool { selfVolatile == "rollout" || volatileStatus == "rollout" }
    /// 파괴광선처럼 쓴 다음 턴에 **움직일 수 없는** 기술
    var mustRecharge: Bool { flags.contains("recharge") || selfVolatile == "mustrecharge" }

    var isContact: Bool { flags.contains("contact") }
    var isPunch: Bool { flags.contains("punch") }
    var isBite: Bool { flags.contains("bite") }
    var isSound: Bool { flags.contains("sound") }
    var isPowder: Bool { flags.contains("powder") }
    /// 손가락흔들기가 부를 수 있는 기술인가 (원작 제외 목록이 그대로 반영돼 있다)
    var metronomeCallable: Bool { flags.contains("metronome") }
    /// 방어로 막히는 기술인가. 막히지 않는다면 방어 관통이다.
    var blockedByProtect: Bool { flags.contains("protect") }
    /// 실전에서 쓸 수 있는 기술인가 (Showdown 이 Past/Unobtainable 로 표시한 것 제외)
    var isUsable: Bool { nonstandard == nil && !isMax && !isZ }
}

/// 실전에서 많이 쓰이는 세팅
struct ShowdownSet: Sendable {
    var movePool: [String] = []
    var item: String?
    var abilities: [String] = []
}

enum Showdown {
    /// Showdown id 로 색인된 기술 데이터
    static let moves: [String: ShowdownMove] = parseMoves()
    /// 종 이름(Showdown id) 으로 색인된 추천 세팅
    static let sets: [String: ShowdownSet] = parseSets()

    /// PokeAPI 의 기술 이름("thunder-wave") → Showdown id("thunderwave")
    static func id(fromPokeAPI name: String) -> String {
        name.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    /// Showdown 표시명("Body Slam") → PokeAPI 이름("body-slam")
    static func pokeAPIName(fromDisplay display: String) -> String {
        display.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    static func move(_ pokeAPIName: String) -> ShowdownMove? {
        moves[id(fromPokeAPI: pokeAPIName)]
    }

    /// 종 이름으로 추천 세팅을 찾는다.
    /// sets.json 의 키는 소문자 id 다 ("snorlax", "raichualola").
    /// PokeAPI 이름("snorlax", "raichu-alola") 과 표시명("Snorlax") 을 모두 받아준다.
    static func set(forSpeciesName name: String) -> ShowdownSet? {
        sets[id(fromPokeAPI: name)]
    }

    /// PokeAPI 의 기술 이름 전체 (하이픈 포함). 실제로 받아올 수 있는 이름은 여기 있는 것뿐이다.
    static let pokeAPIMoveNames: [String] = {
        guard let d = ShowdownData.pokeAPIMoveNamesJSON.data(using: .utf8),
              let a = try? JSONSerialization.jsonObject(with: d) as? [String] else { return [] }
        return a
    }()

    /// 손가락흔들기가 부를 수 있는 기술을 **PokeAPI 이름으로** 돌려준다.
    ///
    /// Showdown id 는 하이픈이 없어(thunderwave) 역변환이 불가능하다.
    /// 그래서 PokeAPI 이름 목록을 훑으면서 Showdown 쪽 플래그를 조회하는 방향으로 간다.
    static var metronomePool: [String] {
        pokeAPIMoveNames.filter { name in
            guard let m = move(name) else { return false }
            return m.metronomeCallable && m.isUsable
        }
    }

    /// PokeAPI 의 특성 이름 전체
    static let pokeAPIAbilityNames: [String] = {
        guard let d = ShowdownData.pokeAPIAbilityNamesJSON.data(using: .utf8),
              let a = try? JSONSerialization.jsonObject(with: d) as? [String] else { return [] }
        return a
    }()

    /// PokeAPI 의 도구 이름 전체
    static let pokeAPIItemNames: [String] = {
        guard let d = ShowdownData.pokeAPIItemNamesJSON.data(using: .utf8),
              let a = try? JSONSerialization.jsonObject(with: d) as? [String] else { return [] }
        return a
    }()

    /// Showdown id → PokeAPI 이름. **역변환은 표로만 가능하다.**
    /// 하이픈 위치를 추측하면 "serenegrace" 를 되살릴 수 없다.
    static let abilityNameByID: [String: String] = {
        Dictionary(pokeAPIAbilityNames.map { (id(fromPokeAPI: $0), $0) },
                   uniquingKeysWith: { a, _ in a })
    }()
    static let itemNameByID: [String: String] = {
        Dictionary(pokeAPIItemNames.map { (id(fromPokeAPI: $0), $0) },
                   uniquingKeysWith: { a, _ in a })
    }()

    // MARK: 도구 · 특성

    /// 도구 데이터 (Showdown id 기준)
    static let items: [String: ShowdownItem] = parseItems()
    /// 특성 데이터 (Showdown id 기준)
    static let abilities: [String: ShowdownAbility] = parseAbilities()

    static func item(_ pokeAPIName: String) -> ShowdownItem? {
        items[id(fromPokeAPI: pokeAPIName)]
    }
    static func ability(_ pokeAPIName: String) -> ShowdownAbility? {
        abilities[id(fromPokeAPI: pokeAPIName)]
    }

    private static func parseItems() -> [String: ShowdownItem] {
        guard let data = ShowdownData.itemsJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: ShowdownItem] = [:]
        for (id, v) in raw {
            guard let d = v as? [String: Any] else { continue }
            var i = ShowdownItem()
            i.flingPower = d["fl"] as? Int
            i.flingStatus = d["fls"] as? String
            i.flingVolatile = d["flv"] as? String
            i.isBerry = d["berry"] != nil
            i.isChoice = d["choice"] != nil
            i.megaStone = d["mega"] as? String
            i.zMoveType = d["zt"] as? String
            i.itemUser = d["user"] as? [String]
            i.nonstandard = d["ns"] as? String
            i.plateType = d["plate"] as? String
            i.boosts = d["bo"] as? [String: Int]
            if let ng = d["ng"] as? [Any], ng.count == 2 {
                i.naturalGiftPower = ng[0] as? Int
                i.naturalGiftType = ng[1] as? String
            }
            i.hooks = Set((d["hooks"] as? [String]) ?? [])
            out[id] = i
        }
        return out
    }

    private static func parseAbilities() -> [String: ShowdownAbility] {
        guard let data = ShowdownData.abilitiesJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: ShowdownAbility] = [:]
        for (id, v) in raw {
            guard let d = v as? [String: Any] else { continue }
            var a = ShowdownAbility()
            a.nonstandard = d["ns"] as? String
            a.isBreakable = d["brk"] != nil
            a.suppressesWeather = d["sw"] != nil
            a.hooks = Set((d["hooks"] as? [String]) ?? [])
            out[id] = a
        }
        return out
    }

    // MARK: 파싱

    private static func parseMoves() -> [String: ShowdownMove] {
        guard let data = ShowdownData.movesJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: ShowdownMove] = [:]
        out.reserveCapacity(raw.count)
        for (id, v) in raw {
            guard let d = v as? [String: Any] else { continue }
            var m = ShowdownMove()
            if let f = d["f"] as? [String] { m.flags = Set(f) }
            m.basePower = d["bp"] as? Int
            m.type = d["ty"] as? String
            m.category = d["cat"] as? String
            m.selfSwitch = d["sw"] != nil
            m.selfDestructMode = d["sd"] as? String
            m.isMax = d["mx"] != nil
            m.isZ = d["z"] != nil
            m.nonstandard = d["ns"] as? String
            if let mh = d["mh"] as? [Int], mh.count == 2 {
                m.multiHitMin = mh[0]; m.multiHitMax = mh[1]
            } else if let mh = d["mh"] as? Int {
                m.multiHitMin = mh; m.multiHitMax = mh
            }
            m.critRatio = d["cr"] as? Int
            m.ohko = d["ko"] != nil
            m.forceSwitch = d["fs"] != nil
            m.volatileStatus = d["vs"] as? String
            m.status = d["st"] as? String
            m.hasCustomCode = (d["cc"] as? Int) == 1
            m.selfVolatile = d["sv"] as? String
            m.recoil = d["rc"] as? [Int]
            m.drain = d["dr"] as? [Int]
            m.heal = d["hl"] as? [Int]
            m.boosts = d["bo"] as? [String: Int]
            m.selfBoosts = d["sb"] as? [String: Int]
            m.selfStatus = d["ss"] as? String
            m.hidesUser = (d["hide"] as? Int) == 1
            m.target = d["tg"] as? String
            out[id] = m
        }
        return out
    }

    private static func parseSets() -> [String: ShowdownSet] {
        guard let data = ShowdownData.setsJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: ShowdownSet] = [:]
        for (name, v) in raw {
            guard let d = v as? [String: Any] else { continue }
            var s = ShowdownSet()
            s.movePool = (d["m"] as? [String] ?? []).map { pokeAPIName(fromDisplay: $0) }
            if let i = d["i"] as? String { s.item = pokeAPIName(fromDisplay: i) }
            s.abilities = (d["a"] as? [String] ?? []).map { pokeAPIName(fromDisplay: $0) }
            out[name] = s
        }
        return out
    }
}

/// Showdown 의 도구 데이터.
///
/// PokeAPI 의 짧은 설명으로는 "맹독구슬을 들면 다음 턴에 맹독" 같은 규칙을
/// 구현할 수 없다. 무엇보다 **목록이 있어서** 우리가 무엇을 빼먹었는지 셀 수 있다.
struct ShowdownItem: Sendable {
    /// 내던지기 위력 (없으면 던질 수 없다)
    var flingPower: Int?
    /// 내던지면 상대가 걸리는 상태이상 (맹독구슬 → 맹독)
    var flingStatus: String?
    /// 내던지면 걸리는 일시 상태 (백금가루 → 풀죽음 등)
    var flingVolatile: String?
    var isBerry = false
    var isChoice = false
    var megaStone: String?
    var zMoveType: String?
    /// 특정 포켓몬만 쓸 수 있는 전용 도구
    var itemUser: [String]?
    var nonstandard: String?
    var plateType: String?
    var boosts: [String: Int]?
    var naturalGiftPower: Int?
    var naturalGiftType: String?
    /// 배틀 중 동작하는 훅 이름들. 하나라도 있으면 구현이 필요한 도구다.
    var hooks: Set<String> = []

    /// 지금 세대에서 실제로 쓸 수 있는 도구인가
    var isUsable: Bool { nonstandard == nil }
    /// 배틀 중 무언가 하는 도구인가 (단순 판매용 아이템 제외)
    var hasBattleEffect: Bool {
        !hooks.isEmpty || isChoice || megaStone != nil || zMoveType != nil
            || boosts != nil || naturalGiftPower != nil
    }
}

/// Showdown 의 특성 데이터
struct ShowdownAbility: Sendable {
    var nonstandard: String?
    /// 틀깨기로 무시되는 특성인가
    var isBreakable = false
    var suppressesWeather = false
    var hooks: Set<String> = []

    var isUsable: Bool { nonstandard == nil }
    var hasBattleEffect: Bool { !hooks.isEmpty || suppressesWeather }
}

/// Showdown 의 종족·폼 표.
///
/// **특수 폼 목록의 원천이다.** 사람이 "특이한 포켓몬" 을 손으로 적어 관리하면
/// 반드시 빠진다 — 새 세대가 나오면 기억해서 갱신해야 하기 때문이다.
/// 이 표는 폼이 **언제 생기는지**를 스스로 말해준다.
struct ShowdownSpecies: Sendable {
    var num: Int = 0
    /// 이 폼의 원종 ("Aegislash")
    var baseSpecies: String?
    /// 폼 이름 ("Blade")
    var forme: String?
    var otherFormes: [String] = []
    /// 전투에만 존재하는 폼 — 값은 되돌아갈 종족 이름이다.
    /// 킬가르도 블레이드·따라큐 들킨모습·메가진화가 모두 여기 잡힌다.
    var battleOnly: String?
    /// 무엇에서 바뀌는가 (지가르데 퍼펙트 등)
    var changesFrom: String?
    /// 이 폼을 만드는 도구 (실버디 메모리·아르세우스 플레이트·메가스톤)
    var requiredItem: String?
    var requiredItems: [String] = []
    /// 이 폼에 필요한 기술 (메가레쿠쟈의 화룡점정, 케르디오의 신비의칼)
    var requiredMove: String?
    var requiredAbility: String?
    var requiredTeraType: String?
    /// 최대 HP 가 고정된 종족 (껍질몬 = 1)
    var maxHP: Int?
    var nonstandard: String?
    var abilities: [String] = []
    var gen: Int = 0

    var isUsable: Bool { nonstandard == nil }
    /// 전투 엔진이 따로 다뤄야 하는 폼인가
    var needsBattleLogic: Bool {
        battleOnly != nil || changesFrom != nil || requiredItem != nil
            || !requiredItems.isEmpty || requiredMove != nil || maxHP != nil
    }
}

extension Showdown {
    /// 종족·폼 표 (Showdown id 기준)
    static let dex: [String: ShowdownSpecies] = {
        guard let data = ShowdownData.dexJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: ShowdownSpecies] = [:]
        for (id, v) in raw {
            guard let d = v as? [String: Any] else { continue }
            var s = ShowdownSpecies()
            s.num = d["num"] as? Int ?? 0
            s.baseSpecies = d["base"] as? String
            s.forme = d["forme"] as? String
            s.otherFormes = (d["other"] as? [String]) ?? []
            s.battleOnly = {
                if let one = d["battleOnly"] as? String { return one }
                if let many = d["battleOnly"] as? [String] { return many.first }
                return nil
            }()
            s.changesFrom = {
                if let one = d["changesFrom"] as? String { return one }
                if let many = d["changesFrom"] as? [String] { return many.first }
                return nil
            }()
            s.requiredItem = d["reqItem"] as? String
            s.requiredItems = (d["reqItems"] as? [String]) ?? []
            s.requiredMove = d["reqMove"] as? String
            s.requiredAbility = d["reqAbility"] as? String
            s.requiredTeraType = d["reqTera"] as? String
            s.maxHP = d["maxHP"] as? Int
            s.nonstandard = d["ns"] as? String
            s.abilities = (d["abilities"] as? [String]) ?? []
            s.gen = d["gen"] as? Int ?? 0
            out[id] = s
        }
        return out
    }()

    /// PokeAPI 가 아는 폼 이름 (팬메이드·CAP 폼을 걸러내는 데 쓴다)
    static let pokeAPIFormNames: Set<String> = {
        guard let d = ShowdownData.pokeAPIFormNamesJSON.data(using: .utf8),
              let a = try? JSONSerialization.jsonObject(with: d) as? [String] else { return [] }
        return Set(a)
    }()

    /// 전투 로직이 필요한 폼 전체 (감사가 훑는 목록).
    ///
    /// **PokeAPI 가 아는 폼만 남긴다.** Showdown 의 pokedex.ts 에는 팬메이드
    /// 메가(Chesnaught-Mega)와 CAP 종족(Ramnarok)이 섞여 있는데, 우리 앱은
    /// PokeTokenBar 도감 + PokeAPI 로만 폼을 만들 수 있어 애초에 나올 수 없다.
    static var specialForms: [(id: String, species: ShowdownSpecies)] {
        dex.filter { entry in
            let sp = entry.value
            guard sp.isUsable, sp.needsBattleLogic, sp.num > 0 else { return false }
            return pokeAPIFormNames.contains(formSlug(sp) ?? "")
        }
        .sorted { $0.key < $1.key }
        .map { (id: $0.key, species: $0.value) }
    }

    /// ShowdownSpecies → PokeAPI 폼 이름 ("Aegislash" + "Blade" → "aegislash-blade")
    static func formSlug(_ sp: ShowdownSpecies) -> String? {
        func slug(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ":", with: "")
        }
        guard let base = sp.baseSpecies else {
            // 폼이 아니라 원종 그 자체 (껍질몬 등)
            return sp.forme == nil ? slug(dexName(of: sp)) : nil
        }
        guard let forme = sp.forme else { return slug(base) }
        return "\(slug(base))-\(slug(forme))"
    }

    /// 표에서 이 종족의 이름을 되찾는다 (원종은 base 가 비어 있다)
    private static func dexName(of sp: ShowdownSpecies) -> String {
        for (id, v) in dex where v.num == sp.num && v.baseSpecies == nil && v.forme == nil {
            return id
        }
        return ""
    }
}
