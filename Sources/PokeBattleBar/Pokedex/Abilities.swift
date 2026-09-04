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

    // --- 확장 (4차) — Showdown 데이터 대조(--datagap)로 찾아낸 것들 ---
    //
    // 이름을 아는 것만 고치던 방식을 버리고, 목록을 데이터에서 받아
    // 위에서부터 메웠다. 싱글에서 의미가 있는 것만 넣는다.

    /// 에어레이트·페어리스킨 등 — 노말 기술이 다른 타입이 되고 위력도 오른다.
    /// 노말스킨은 `from` 이 nil 이다 (**모든** 기술이 노말이 된다).
    case moveTypeConversion(from: PType?, to: PType, multiplier: Double)
    /// 변환자재·리베로 — 쓴 기술의 타입으로 자신이 변한다
    case userTypeMatchesMove
    /// 일렉트릭메이커 등 — 등장 시 필드를 만든다
    case terrainOnEntry(Terrain)
    /// 끝의대지·시작의바다·델타스트림 — 다른 날씨로 덮어쓸 수 없다
    case weatherLock(Weather)
    /// 에어록·노말스킨(구름) — 날씨 효과 자체를 없앤다
    case weatherSuppress
    /// 퍼코트 — 방어가 두 배 (물리 피해만 줄어든다)
    case defenseMultiplier(Stat, Double)
    /// 아이스스케일 — 특수 기술 피해 절반
    case damageTakenByClass(DamageClass, Double)
    /// 후카후카 — 접촉 기술 절반, 불꽃 두 배
    case fluffy
    /// 초식피부 — 특정 필드에서 방어 상승
    case terrainStatBoost(Terrain, Stat, Double)
    /// 브레인포스 — 효과가 굉장할 때 추가 배율
    case superEffectiveBoost(Double)
    /// 무자비 — 특정 상태이상인 상대에게 반드시 급소
    case critVsStatus(Ailment)
    /// 방탄 — 특정 플래그가 붙은 기술이 통하지 않는다
    case flagImmunity(MoveFlagKind)
    /// 황금몸(굿애즈골드) — 변화기가 통하지 않는다
    case statusMoveImmunity
    /// 불요의검·부동의방패 — 등장 시 능력 상승
    case boostOnEntry(Stat, Int)
    /// 매지컬아머(미러아머) — 능력 하락을 되돌려준다
    case mirrorArmor
    /// 날카로운눈 — 명중률 하락을 막는다 (명중률은 Stat 이 아니다)
    case accuracyDropImmunity
    /// 노기어깨(앵거포인트) — 급소를 맞으면 공격이 최대가 된다
    case angerPoint
    /// 노기의비늘(앵거셸) — HP 절반 이하가 되면 공방이 바뀐다
    case angerShell
    /// 벌서크 — HP 절반 이하가 되면 특공 상승
    case berserk(Stat, Int)
    /// 목화솜(코튼다운) — 맞으면 상대 스피드가 내려간다
    case cottonDown(Stat, Int)
    /// 미라·잔향 — 접촉해 온 상대의 특성을 바꿔버린다
    case abilityInfect(String)
    /// 심안(이너즈아웃) — 쓰러질 때 남은 HP 만큼 되돌려준다
    case innardsOut
    /// 변색 — 맞은 기술의 타입으로 변한다
    case colorChange
    /// 일렉트릭변환(일렉트로모포시스) — 맞으면 다음 전기 기술이 강해진다
    case chargeWhenHit
    /// 저주받은육체(퍼리시바디) — 접촉해 오면 양쪽에 멸망의노래
    case perishBody
    /// 크리티컬 확률 단계를 올리는 특성 (대운·저격수는 별도)
    case critStageBoost(Int)
    /// 심록(스나이프샷) 등 — 상대 진영 특성을 무시하고 관통한다.
    /// 인필트레이터 — 리플렉터·빛의장막·대타출동을 무시한다.
    case infiltrator
    /// 원격(롱리치) — 접촉 판정이 붙지 않는다
    case longReach
    /// 서투름(클럿지) — 자기 도구가 작동하지 않는다
    case klutz
    /// 매지션 — 때리면 상대 도구를 빼앗는다
    case magician
    /// 변덕쟁이(무디) — 턴마다 하나는 +2, 하나는 -1
    case moody
    /// 수확(하베스트) — 먹은 열매를 확률로 되돌린다
    case harvest(percent: Int)
    /// 볼주머니 — 열매를 먹으면 HP 도 회복한다
    case cheekPouch(fraction: Int)
    /// 되새김(커드추드) — 먹은 열매를 다음 턴에 한 번 더 먹는다
    case cudChew
    /// 숙성(라이픈) — 열매 효과가 두 배가 된다
    case ripen
    /// 정화의소금 — 상태이상에 걸리지 않고 고스트 기술을 반감한다
    case purifyingSalt
    /// 절대잠듦(코머토스) — 항상 잠든 상태로 취급되지만 행동할 수 있다
    case comatose
    /// 균사의힘(미셀리움마이트) — 변화기를 나중에 쓰지만 상대 특성을 무시한다
    case myceliumMight
    /// 파문의힘 — 상대 방어를 무시한다 (스톨워트·프로펠러테일: 노려대상 고정)
    case ignoreRedirection
    /// 불굴의주먹(언신피스트) — 방어를 무시하고 때린다
    case unseenFist
    /// 재의검(소드오브루인) 4종 — 상대의 특정 능력치를 0.75배로 만든다
    case ruin(Stat, Double)
    /// 다크오라·페어리오라 — 그 타입 기술이 **양쪽 모두** 강해진다
    case aura(PType, Double)
    /// 오라브레이크 — 오라를 반대로 뒤집는다
    case auraBreak
    /// 나이트메어(배드드림) — 잠든 상대가 턴마다 깎인다
    case badDreams(fraction: Int)
    /// 예지몽·위험예지·전율 — 등장 시 정보를 알려준다 (효과는 표시뿐)
    case revealOnEntry
    /// 하드론엔진·오리하르콘펄스 — 등장 시 필드/날씨를 만들고 자기 능력을 올린다
    case surgeAndBoost(Terrain?, Weather?, Stat, Double)
    /// 고대활성·쿼크차지 — 날씨/필드나 부스트에너지로 가장 높은 능력치가 오른다
    case paradoxBoost(Weather?, Terrain?)

    // --- 확장 (5차) ---

    /// 여왕의위엄·갑옷꼬리·눈부심 — 선공 기술을 막는다
    case priorityBlock
    /// 옷무늬(디스가이즈)·아이스페이스 — 첫 공격을 한 번 무효로 한다
    case oneHitShield(formAfter: String?)
    /// 스킬링크 — 연속 기술이 반드시 최대 횟수 맞는다
    case skillLink
    /// 슬로스타트 — 5턴 동안 공격과 스피드가 반감된다
    case slowStart(turns: Int)
    /// 배드컴패니(스텐치) — 확률로 상대를 풀죽게 한다
    case addFlinch(percent: Int)
    /// 원더스킨 — 상대의 변화기 명중률이 절반이 된다
    case statusMoveEvasion(Double)
    /// 갈팡질팡(탱글드피트) — 혼란 중에 회피율이 오른다
    case evasionWhenConfused(Double)
    /// 서프라이더 — 특정 필드에서 스피드가 두 배
    case terrainSpeedBoost(Terrain, Double)
    /// 총대장(슈프림오버로드) — 쓰러진 아군 수만큼 위력이 오른다
    case supremeOverlord(perFaint: Double)
    /// 독쇠사슬 — 접촉 공격 시 확률로 맹독
    case toxicChain(percent: Int)
    /// 파스텔베일 — 독 상태이상에 걸리지 않는다
    case poisonImmunityPlus
    /// 스크린클리너 — 등장 시 양쪽 화면을 없앤다
    case screenCleaner
    /// 트랜지스터형 트랩 — 상대를 도망칠 수 없게 만든다 (개미지옥·그림자밟기)
    case trapFoe(PType?)
    /// 흡착(석션컵) — 강제 교체당하지 않는다
    case suctionCups
    /// 노말스킨류 특성 무력화 (뉴트럴가스) — 양쪽 특성이 사라진다
    case neutralizingGas
    /// 미믹(미미크리) — 필드에 따라 자기 타입이 바뀐다
    case mimicry
    /// 변신(임포스터) — 등장 시 상대로 변신한다
    case imposter
    /// 부모의사랑 — 한 번 더, 약하게 때린다
    case parentalBond(Double)
    /// 도둑질(픽포켓)·방랑령 — 접촉해 온 상대의 도구/특성을 가져온다
    case stealOnContact(item: Bool)
    /// 기회주의자(오포튜니스트) — 상대가 능력을 올리면 같이 오른다
    case opportunist
    /// 독가스가루(톡식데브리) — 물리 공격을 맞으면 상대 진영에 독압정을 깐다
    case hazardWhenHit(Hazard, DamageClass)
    /// 오거폰 — 쓰고 있는 가면에 따라 오르는 능력치가 다르다
    case embodyAspect
    /// 아주달콤한꿀 — 등장 시 상대 회피율이 내려간다
    /// (회피율은 Stat 이 아니라 별도 필드라서 전용 케이스가 필요하다)
    case lowerFoeEvasionOnEntry
    /// 배고픔스위치·실드다운·배틀스위치 — 턴마다/조건에 따라 폼이 바뀐다.
    /// FormChange 가 규칙을 갖고 있지 않아 표시만 한다.
    case formSwitchDisplay

    /// 더블배틀 전용 — 1대1 에서는 발동할 수 없다 (미구현이 아니라 해당 없음)
    case doublesOnly
}

/// 기술 플래그 종류 (철주먹·옹골찬턱용)
enum MoveFlagKind: String, Codable, Hashable, Sendable {
    case punch, bite, sound, powder, contact, bullet, slicing, wind
}

struct AbilityDef: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var koName: String
    var shortEffect: String
    /// PokéAPI 의 한글 설명 (flavor_text). effect_entries 는 영어/프랑스어가 섞여 온다.
    var koFlavor: String = ""
    var isHidden: Bool = false
    var kind: AbilityKind

    var display: String { koName.isEmpty ? name : koName }
    /// 화면에 보여줄 설명 — 한글이 있으면 한글
    var description: String { koFlavor.isEmpty ? shortEffect : koFlavor }
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
    /// 한글 flavor text — 여러 버전 중 가장 최근 것
    static func koFlavor(_ raw: Any?) -> String {
        guard let arr = raw as? [[String: Any]] else { return "" }
        var last = ""
        for e in arr {
            guard let l = e["language"] as? [String: Any],
                  let n = l["name"] as? String, n == "ko",
                  let t = e["flavor_text"] as? String else { continue }
            last = t.replacingOccurrences(of: "\n", with: " ")
        }
        return last
    }

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
        case "stall":           return .priorityBoost(nil, -1)
        case "pure-power":      return .attackMultiplier(2.0)
        case "gorilla-tactics": return .statMultiplier(.attack, 1.5)
        case "transistor":      return .pinchBoost(.electric, 1.3)
        case "dragons-maw":     return .pinchBoost(.dragon, 1.5)
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
        case "water-absorb":                   return .levitateLike(.water, 0.25)
        case "volt-absorb":                    return .levitateLike(.electric, 0.25)
        case "flash-fire":                     return .levitateLike(.fire, 0.0)
        case "sap-sipper":                     return .levitateLike(.grass, 0.0)
        case "motor-drive", "lightning-rod":   return .levitateLike(.electric, 0.0)
        case "storm-drain":                    return .levitateLike(.water, 0.0)
        // 물먹기 — 물 기술을 맞으면 방어가 크게 오른다 (무효가 아니다)
        case "water-compaction":               return .boostWhenHit(.water, .defense, 2)
        case "steam-engine":                   return .boostWhenHit(nil, .speed, 6)

        // ─────────────────────────────────────────────────────────────
        // 4차 — Showdown 데이터 대조로 찾아낸 것들 (--datagap)
        // ─────────────────────────────────────────────────────────────

        // 타입 변환 스킨. 노말 기술이 다른 타입이 되고 위력도 1.2배가 된다.
        case "aerilate":    return .moveTypeConversion(from: .normal, to: .flying, multiplier: 1.2)
        case "pixilate":    return .moveTypeConversion(from: .normal, to: .fairy, multiplier: 1.2)
        case "galvanize":   return .moveTypeConversion(from: .normal, to: .electric, multiplier: 1.2)
        case "refrigerate": return .moveTypeConversion(from: .normal, to: .ice, multiplier: 1.2)
        // 노말스킨은 **모든** 기술을 노말로 바꾼다
        case "normalize":   return .moveTypeConversion(from: nil, to: .normal, multiplier: 1.2)
        case "liquid-voice": return .moveTypeConversion(from: nil, to: .water, multiplier: 1.0)
        case "protean", "libero": return .userTypeMatchesMove

        // 필드를 만드는 특성
        case "electric-surge": return .terrainOnEntry(.electric)
        case "grassy-surge":   return .terrainOnEntry(.grassy)
        case "misty-surge":    return .terrainOnEntry(.misty)
        case "psychic-surge":  return .terrainOnEntry(.psychic)

        // 날씨를 고정하는 특성 (다른 날씨로 덮어쓸 수 없다)
        case "desolate-land":  return .weatherLock(.sun)
        case "primordial-sea": return .weatherLock(.rain)
        // 델타스트림은 "강한 바람" 이라 우리 Weather 에 대응이 없다 —
        // 비행 타입의 약점을 지우는 효과라 날씨 억제로 근사한다.
        case "delta-stream":   return .weatherSuppress
        case "air-lock", "cloud-nine": return .weatherSuppress

        // 방어 배율
        case "fur-coat":    return .defenseMultiplier(.defense, 2.0)
        case "ice-scales":  return .damageTakenByClass(.special, 0.5)
        case "fluffy":      return .fluffy
        case "grass-pelt":  return .terrainStatBoost(.grassy, .defense, 1.5)
        case "punk-rock":   return .damageTakenByClass(.special, 0.5)

        // 공격 배율 / 급소
        case "neuroforce":  return .superEffectiveBoost(1.25)
        case "merciless":   return .critVsStatus(.poison)
        case "super-luck":   return .critStageBoost(1)

        // 무효 / 흡수
        case "bulletproof":      return .flagImmunity(.bullet)
        case "earth-eater":      return .levitateLike(.ground, 0.25)
        case "well-baked-body":  return .absorbAndBoost(.fire, .defense, 2)
        case "wind-rider":       return .absorbAndBoost(.flying, .attack, 1)
        case "thermal-exchange": return .absorbAndBoost(.fire, .attack, 1)
        case "good-as-gold":     return .statusMoveImmunity

        // 능력 하락 무효 — 기존 케이스로 충분한 것들
        case "full-metal-body", "white-smoke": return .clearBody
        case "hyper-cutter":  return .statDropImmunity([.attack])
        case "big-pecks":     return .statDropImmunity([.defense])
        // 날카로운눈은 **명중률** 하락을 막는다. 명중률·회피율은 Stat 이
        // 아니라 별도 필드(accuracyStage)라서 statDropImmunity 로 표현할 수
        // 없다 — 전용 케이스를 쓴다.
        case "keen-eye", "minds-eye", "illuminate": return .accuracyDropImmunity
        case "guard-dog":     return .clearBody
        case "mirror-armor":  return .mirrorArmor
        case "inner-focus":   return .flinchImmunity

        // 능력이 내려가면 되돌아 오르는 특성
        case "competitive":   return .boostWhenHit(nil, .spAttack, 2)
        case "defiant":       return .boostWhenHit(nil, .attack, 2)

        // 등장 시 능력 상승
        case "intrepid-sword":   return .boostOnEntry(.attack, 1)
        case "dauntless-shield": return .boostOnEntry(.defense, 1)

        // 등장 시 정보 (효과는 표시뿐 — 원작도 그렇다)
        case "anticipation", "forewarn", "frisk": return .revealOnEntry

        // 맞았을 때 반응
        case "anger-point":       return .angerPoint
        case "anger-shell":       return .angerShell
        case "berserk":           return .berserk(.spAttack, 1)
        case "cotton-down":       return .cottonDown(.speed, 1)
        case "mummy", "lingering-aroma": return .abilityInfect("mummy")
        case "innards-out":       return .innardsOut
        case "color-change":      return .colorChange
        case "electromorphosis", "wind-power": return .chargeWhenHit
        case "perish-body":       return .perishBody
        case "stamina":           return .boostWhenHit(nil, .defense, 1)
        case "seed-sower":        return .terrainOnEntry(.grassy)

        // 관통 / 접촉
        case "infiltrator":  return .infiltrator
        case "long-reach":   return .longReach
        case "unseen-fist":  return .unseenFist
        case "propeller-tail", "stalwart": return .ignoreRedirection
        case "mycelium-might": return .myceliumMight

        // 도구 관련
        case "klutz":        return .klutz
        case "magician":     return .magician
        case "harvest":      return .harvest(percent: 50)
        case "cheek-pouch":  return .cheekPouch(fraction: 3)
        case "cud-chew":     return .cudChew
        case "ripen":        return .ripen

        // 상태 / 잠듦
        case "purifying-salt": return .purifyingSalt
        case "comatose":       return .comatose
        case "bad-dreams":     return .badDreams(fraction: 8)

        // 재앙 4종 — 상대의 능력치를 0.75배로 만든다
        case "sword-of-ruin":    return .ruin(.defense, 0.75)
        case "beads-of-ruin":    return .ruin(.spDefense, 0.75)
        case "tablets-of-ruin":  return .ruin(.attack, 0.75)
        case "vessel-of-ruin":   return .ruin(.spAttack, 0.75)

        // 오라
        case "dark-aura":   return .aura(.dark, 1.33)
        case "fairy-aura":  return .aura(.fairy, 1.33)
        case "aura-break":  return .auraBreak

        // 등장 시 필드·날씨를 만들고 자기 능력도 올린다
        case "hadron-engine":    return .surgeAndBoost(.electric, nil, .spAttack, 1.33)
        case "orichalcum-pulse": return .surgeAndBoost(nil, .sun, .attack, 1.33)

        // 고대활성·쿼크차지 — 조건이 맞으면 가장 높은 능력치가 1.3배
        case "protosynthesis": return .paradoxBoost(.sun, nil)
        case "quark-drive":    return .paradoxBoost(nil, .electric)

        // 변덕쟁이
        case "moody":        return .moody

        // ── 5차 ──

        // 선공 기술을 막는다
        case "queenly-majesty", "armor-tail", "dazzling": return .priorityBlock

        // 첫 공격을 한 번 무효로 한다
        case "disguise":  return .oneHitShield(formAfter: "mimikyu-busted")
        case "ice-face":  return .oneHitShield(formAfter: "eiscue-noice")

        case "skill-link":  return .skillLink
        case "slow-start":  return .slowStart(turns: 5)
        case "stench":      return .addFlinch(percent: 10)
        case "wonder-skin": return .statusMoveEvasion(0.5)
        case "tangled-feet": return .evasionWhenConfused(0.5)
        case "surge-surfer": return .terrainSpeedBoost(.electric, 2.0)
        case "supreme-overlord": return .supremeOverlord(perFaint: 0.1)
        case "toxic-chain":  return .toxicChain(percent: 30)
        case "toxic-debris": return .hazardWhenHit(.toxicSpikes, DamageClass.physical)
        case "pastel-veil":  return .poisonImmunityPlus
        case "screen-cleaner": return .screenCleaner
        case "suction-cups": return .suctionCups
        case "neutralizing-gas": return .neutralizingGas
        case "mimicry":      return .mimicry
        case "imposter":     return .imposter
        case "parental-bond": return .parentalBond(0.25)
        case "pickpocket":   return .stealOnContact(item: true)
        case "wandering-spirit": return .stealOnContact(item: false)
        case "opportunist":  return .opportunist

        // 상대를 묶는 특성 — 교체룰이 켜져 있을 때만 의미가 있다
        case "shadow-tag":   return .trapFoe(nil)
        case "arena-trap":   return .trapFoe(nil)
        case "magnet-pull":  return .trapFoe(.steel)

        // 오거폰의 가면 특성.
        //
        // Showdown 은 가면마다 별개 특성(embodyaspectteal …)으로 나눠 두지만
        // **PokeAPI 에는 embody-aspect 하나뿐**이다. 어느 능력치가 오르는지는
        // 특성 이름이 아니라 폼(가면)이 결정하므로 엔진에서 폼을 보고 정한다.
        case "embody-aspect":  return .embodyAspect
        case "supersweet-syrup":        return .lowerFoeEvasionOnEntry

        // 폼이 바뀌는데 FormChange 에 규칙이 없는 것들 — 표시만 한다.
        // 규칙을 넣기 전에 표시라도 맞춰두면 "구현했다" 는 오해가 없다.
        case "hunger-switch", "shields-down", "stance-change",
             "power-construct", "gulp-missile", "illusion",
             "zero-to-hero", "tera-shift", "teraform-zero":
            return .formSwitchDisplay

        // 교체가 있어야만 의미가 있는 특성 (우리 1대1 에는 자발적 교체가 없다)
        case "emergency-exit", "wimp-out", "stakeout":
            return .doublesOnly

        // 성별을 다루지 않아 판정할 수 없는 특성
        case "rivalry", "cute-charm":
            return .doublesOnly

        // ── 더블배틀 전용 — 1대1 에서는 발동할 수 없다 ──
        //
        // 미구현이 아니라 **해당 없음**이다. 이렇게 표시해두지 않으면
        // 감사 목록에 영원히 남아 실제로 빠진 것을 가린다.
        case "costar", "curious-medicine", "hospitality",
             "power-of-alchemy", "receiver", "friend-guard", "power-spot",
             "flower-veil", "sweet-veil", "aroma-veil", "healer", "battery",
             "symbiosis", "commander", "victory-star", "plus", "minus",
             "telepathy", "battle-bond", "as-one-glastrier", "as-one-spectrier",
             "chilling-neigh", "grim-neigh", "soul-heart", "poison-puppeteer":
            return .doublesOnly

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
                             koFlavor: Self.koFlavor(j["flavor_text_entries"]),
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
