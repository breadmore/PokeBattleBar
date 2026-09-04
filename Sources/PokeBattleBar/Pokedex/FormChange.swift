import Foundation

/// 폼 체인지.
///
/// **PokeTokenBar 의 데이터는 건드리지 않는다.** 도감은 그쪽에서 오고,
/// 어떤 폼으로 싸울지는 PokeBattleBar 가 자기 저장소(loadouts.json) 에만 기록한다.
/// 폼마다 타입과 종족값이 다르므로 배틀에 실제로 반영된다.
enum FormChange {

    /// 전투 전에 고를 수 있는 폼 (도구·조건 폼).
    /// 메가·거다이맥스는 배틀 중 변신이라 여기서 제외한다.
    static func selectable(for sp: SpeciesDef) -> [String] {
        sp.altForms.filter { name in
            !name.contains("-mega") && !name.hasSuffix("-gmax")
                && !name.contains("-totem") && !name.contains("-cap")
                // 지역폼도 고를 수 있다.
                //
                // PokeTokenBar 도감은 전국번호(#555)만 들고 있어 얼음 불비달마를
                // 따로 구분하지 않는다. 그래서 여기서 폼으로 고르게 한다 —
                // 폼 선택은 우리 loadouts.json 에만 적히므로 도감은 그대로다.
                // 배틀 중 자동 변신하는 폼은 고르는 대상이 아니다
                && !isAutoForm(name)
        }
    }

    /// 배틀 중 특성으로 자동 변신하는 폼인가 (캐스퐁·불비달마·체리꼬·약어리)
    static func isAutoForm(_ name: String) -> Bool {
        let autoSuffixes = ["-sunny", "-rainy", "-snowy", "-zen", "-sunshine",
                            "-overcast", "-school", "-busted", "-hangry"]
        return autoSuffixes.contains { name.hasSuffix($0) }
    }

    /// 폼 이름을 사람이 읽을 수 있게.
    /// 지역폼은 "가라르 달마모드"처럼 지역과 폼 이름을 붙여 읽는다.
    static func label(_ name: String) -> String {
        for (tag, ko) in regions where name.contains(tag) {
            let rest = name.replacingOccurrences(of: tag, with: "")
            let inner = plainLabel(rest)
            // 지역 표기만 있거나 "노말" 이면 지역명만 쓴다 ("가라르 노말" 은 어색하다)
            if inner == rest || inner == "노말" { return ko }
            return "\(ko) \(inner)"
        }
        return plainLabel(name)
    }

    private static func plainLabel(_ name: String) -> String {
        for (suffix, ko) in labels where name.hasSuffix(suffix) { return ko }
        return name
    }

    private static let regions: [(String, String)] = [
        ("-alola", "알로라"), ("-galar", "가라르"),
        ("-hisui", "히스이"), ("-paldea", "팔데아"),
    ]

    private static let labels: [(String, String)] = [
        ("-heat", "히트"), ("-wash", "워시"), ("-frost", "프로스트"),
        ("-fan", "팬"), ("-mow", "모우"),
        ("-attack", "어택"), ("-defense", "디펜스"), ("-speed", "스피드"),
        ("-normal", "노말"),
        ("-origin", "오리진"), ("-altered", "어나더"),
        ("-sky", "스카이"), ("-land", "랜드"),
        ("-therian", "영물"), ("-incarnate", "화신"),
        ("-black", "블랙"), ("-white", "화이트"),
        ("-resolute", "각오"), ("-ordinary", "평소"),
        ("-aria", "보이스"), ("-pirouette", "스텝"),
        ("-standard", "노말"), ("-zen", "달마모드"),
        ("-sunny", "쾌청"), ("-rainy", "비"), ("-snowy", "눈"),
        ("-sunshine", "포지티브"), ("-overcast", "네거티브"),
        ("-solo", "단독"), ("-school", "어군"),
        ("-disguised", "화장"), ("-busted", "들킴"),
        ("-full-belly", "만복"), ("-hangry", "허기"),
        ("-combat", "콤바트"), ("-blaze", "블레이즈"), ("-aqua", "아쿠아")
    ]

    // MARK: 배틀 중 자동 변신

    /// 자동 변신 조건. 특성으로 판정한다.
    enum AutoRule: Sendable {
        /// 날씨에 따라 폼이 바뀐다 (캐스퐁)
        case byWeather([Weather: String], base: String)
        /// 쾌청에서만 바뀐다 (체리꼬)
        case inSun(String, base: String)
        /// HP 가 기준 이하로 떨어지면 (불비달마 달마모드)
        case belowHP(Double, String, base: String)
        /// HP 가 기준 이상일 때만 유지 (약어리 어군)
        case aboveHP(Double, String, base: String)
    }

    /// 특성 이름 → 자동 변신 규칙
    /// - Parameter form: 지금 쓰고 있는 폼 이름 (예: "darmanitan-galar-standard").
    ///   가라르 불비달마처럼 **같은 특성인데 폼 이름이 다른** 경우가 있다.
    static func autoRule(ability: String, speciesID: Int, form: String? = nil) -> AutoRule? {
        switch ability {
        case "forecast":
            return .byWeather([.sun: "castform-sunny",
                               .rain: "castform-rainy",
                               .snow: "castform-snowy"],
                              base: "castform")
        case "flower-gift":
            return .inSun("cherrim-sunshine", base: "cherrim")
        case "zen-mode":
            // 가라르 불비달마의 달마모드는 **얼음/불꽃**이고 폼 이름도 따로다.
            // 이걸 안 보면 얼음 불비달마가 관동 달마모드 스프라이트로 변한다.
            if let form, form.contains("-galar") {
                return .belowHP(0.5, "darmanitan-galar-zen",
                                base: "darmanitan-galar-standard")
            }
            return .belowHP(0.5, "darmanitan-zen", base: "darmanitan-standard")
        case "schooling":
            return .aboveHP(0.25, "wishiwashi-school", base: "wishiwashi-solo")
        default:
            return nil
        }
    }

    /// 배틀 중 폼을 바꾸는 특성 — **실제로 규칙이 있는 것만** 넣는다.
    /// `autoRule` 과 이 목록이 어긋나면 "구현됐다고 표시만 하고 아무 일도
    /// 안 하는" 특성이 생기므로, 특성 분류(AbilityKind)도 이 목록을 본다.
    static let autoAbilityNames: Set<String> = [
        "forecast", "flower-gift", "zen-mode", "schooling",
    ]

    /// 자동 변신 특성인가 (UI 에서 "배틀 중 자동" 이라고 알려준다)
    static func isAutoAbility(_ name: String) -> Bool {
        autoAbilityNames.contains(name)
    }
}
