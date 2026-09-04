import Foundation

/// **우리가 무엇을 빼먹었는지 데이터가 직접 말하게 한다.**
///
/// 지금까지는 사용자가 "오로라베일은 효과가 없어?" 하고 이름을 대주면 그것만
/// 고쳤다. 그러면 이름을 모르는 것은 영원히 안 고쳐진다.
///
/// Showdown 은 도구 583개·특성 321개를 배틀 훅(onResidual, onModifyDamage …)
/// 까지 구조화해서 갖고 있다. 그 목록과 우리 구현을 맞춰보면 빈칸이 나온다.
///
///     PokeBattleBar --datagap
///     PokeBattleBar --datagap --all      (구현된 것까지 전부 나열)
enum DataGapAudit {

    static func run(verbose: Bool) async -> Bool {
        print("=== 데이터 대조 (Showdown 기준) ===\n")
        var ok = true
        ok = auditItems(verbose: verbose) && ok
        ok = auditAbilities(verbose: verbose) && ok
        ok = auditFlingTable(verbose: verbose) && ok
        ok = auditDeadCases() && ok
        ok = auditSpecialForms(verbose: verbose) && ok
        return ok
    }

    // MARK: 특수 폼

    /// **특수 폼을 데이터에서 뽑아 우리 구현과 대조한다.**
    ///
    /// 손으로 "특이한 포켓몬 목록" 을 관리하면 새 세대가 나올 때마다
    /// 사람이 기억해서 갱신해야 하고, 그러면 반드시 빠진다.
    /// pokedex.ts 의 battleOnly·changesFrom·requiredItem·requiredMove·maxHP 가
    /// "이 폼은 언제 생기는가" 를 스스로 말해주므로 그걸 기준으로 삼는다.
    private static func auditSpecialForms(verbose: Bool) -> Bool {
        let forms = Showdown.specialForms
        print("-- 특수 폼 (pokedex.ts 기준) --")
        print("  전투 로직이 필요한 폼 \(forms.count)개")

        // 무엇이 폼을 만드는가로 묶는다. 우리 구현도 그 단위로 되어 있다.
        var groups: [String: [String]] = [:]
        var handled: [String: Bool] = [:]
        for (id, sp) in forms {
            let (bucket, isHandled) = classify(id: id, species: sp)
            groups[bucket, default: []].append(sp.baseSpecies.map {
                "\($0)\(sp.forme.map { "-\($0)" } ?? "")"
            } ?? id)
            // 한 분류 안에서 하나라도 미구현이면 그 분류를 미구현으로 본다
            handled[bucket] = (handled[bucket] ?? true) && isHandled
        }

        var allOK = true
        for bucket in groups.keys.sorted() {
            let list = groups[bucket]!
            let done = handled[bucket] ?? false
            let mark = done ? "✓" : "·"
            print("  \(mark) \(bucket) — \(list.count)개")
            if verbose || !done {
                let shown = verbose ? list : Array(list.prefix(8))
                print("      \(shown.joined(separator: ", "))"
                      + (!verbose && list.count > 8 ? " … +\(list.count - 8)" : ""))
            }
            if !done { allOK = false }
        }
        print(allOK ? "  ✓ 분류마다 구현이 있다\n"
                    : "  (· 표시는 아직 규칙이 없는 분류다 — 목록이 곧 할 일이다)\n")
        // 남은 것이 있다고 실패로 만들지는 않는다. 목록을 보여주는 것이 목적이다.
        return true
    }

    /// 이 폼이 어떤 장치로 생기는지, 그리고 우리가 그 장치를 구현했는지.
    private static func classify(id: String, species sp: ShowdownSpecies)
    -> (bucket: String, handled: Bool) {
        let ability = sp.abilities.first.map { AbilityCatalog.kind(for: slugify($0)) }

        // 최대 HP 가 고정된 종족 (껍질몬)
        if sp.maxHP != nil {
            return ("최대 HP 고정 (껍질몬)", false)
        }
        // 도구가 폼을 정하는 것들.
        //
        // **메가진화는 battleOnly 가 없다** — reqItem 만 있다. 그래서 폼 이름으로
        // 판정한다. 예전에는 battleOnly 를 요구해서 메가 100여 종이 전부
        // "미구현" 으로 잡혔다 (실제로는 megaStone 표로 한꺼번에 처리한다).
        if sp.requiredItem != nil || !sp.requiredItems.isEmpty {
            let item = sp.requiredItem ?? sp.requiredItems.first ?? ""
            let slug = slugify(item)
            let forme = sp.forme ?? ""
            if forme.hasPrefix("Mega") {
                return ("메가스톤", true)                      // megaStone 표
            }
            if forme == "Primal" {
                return ("원시회귀 구슬", true)                  // primalOrb
            }
            if forme == "Ultra" {
                return ("울트라버스트 (미지원)", false)
            }
            if slug.hasSuffix("-plate") || slug.hasSuffix("-memory") || slug.hasSuffix("-drive") {
                return ("도구가 타입·폼을 정한다 (아르세우스·실버디·게노세크트)", false)
            }
            let known = ItemCatalog.kind(for: slug, category: "held-items", effect: "") != .none
            return ("도구가 폼을 정한다 (\(slug))", known)
        }
        // 기술을 배워야 생기는 폼 (메가레쿠쟈·케르디오)
        if sp.requiredMove != nil {
            return ("기술이 폼을 정한다 (\(slugify(sp.requiredMove!)))", false)
        }
        // 테라스탈 폼 — 우리는 테라스탈을 다루지 않는다
        if sp.requiredTeraType != nil {
            return ("테라스탈 폼 (미지원)", false)
        }
        // 특성이 전투 중에 바꾸는 폼
        if let ability, ability != .none {
            let name = sp.abilities.first ?? ""
            switch ability {
            case .autoFormChange:
                return ("특성이 자동으로 바꾼다 (\(slugify(name)))", true)
            case .oneHitShield:
                return ("한 번 막고 폼이 바뀐다 (\(slugify(name)))", true)
            case .stanceChange:
                return ("배틀스위치", true)
            case .imposter:
                return ("등장 시 변신 (임포스터)", true)
            case .formSwitchDisplay:
                return ("특성이 바꾸지만 규칙 미구현 (\(slugify(name)))", false)
            default:
                break
            }
        }
        // 다이맥스 전용 폼
        if id.hasSuffix("gmax") {
            return ("거다이맥스", true)
        }
        // 그 외 전투 전용 폼 (합체·울트라버스트 등)
        if sp.battleOnly != nil {
            return ("그 외 전투 전용 폼", false)
        }
        return ("전투 밖에서 정해지는 폼 (지역폼·연출폼)", true)
    }

    /// "Rusted Sword" → "rusted-sword"
    private static func slugify(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    // MARK: 죽은 case

    /// 오타로 영원히 실행되지 않는 case 가 있으면 **실패**로 처리한다.
    /// 이건 "아직 구현 안 함" 이 아니라 버그다.
    private static func auditDeadCases() -> Bool {
        let (ab, it) = deadCaseNames()
        print("-- 존재하지 않는 이름을 가진 case --")
        if ab.isEmpty && it.isEmpty {
            print("  ✓ 없음\n")
            return true
        }
        for n in ab { print("  ✗ 특성 \"\(n)\" — PokeAPI 에 이런 이름이 없다") }
        for n in it { print("  ✗ 도구 \"\(n)\" — PokeAPI 에 이런 이름이 없다") }
        print("")
        return false
    }

    // MARK: 도구

    private static func auditItems(verbose: Bool) -> Bool {
        // 배틀에서 무언가 하는데 지금 세대에 존재하는 도구만 본다.
        // 열매·플레이트·Z크리스탈·메가스톤은 표로 한꺼번에 처리하므로
        // 개별 이름이 아니라 그룹 단위로 구현 여부를 판정한다.
        var missing: [String] = []
        var covered = 0
        var skipped = 0

        for (id, it) in Showdown.items.sorted(by: { $0.key < $1.key }) {
            guard it.isUsable, it.hasBattleEffect else { skipped += 1; continue }
            let slug = itemSlug(id)
            if isCovered(slug: slug, item: it) { covered += 1 } else { missing.append(slug) }
        }

        print("-- 도구 --")
        print("  배틀 효과가 있는 도구 \(covered + missing.count)개 중 \(covered)개 구현")
        print("  (효과 없음·과거 세대 \(skipped)개는 제외)")
        if missing.isEmpty {
            print("  ✓ 빠진 도구 없음\n")
            return true
        }
        print("  남은 도구 \(missing.count)개:")
        for slug in (verbose ? missing : Array(missing.prefix(40))) {
            let it = Showdown.item(slug)
            let hooks = it?.hooks.sorted().joined(separator: ",") ?? ""
            print("    · \(slug)\(hooks.isEmpty ? "" : "  [\(hooks)]")")
        }
        if !verbose, missing.count > 40 {
            print("    … 그 외 \(missing.count - 40)개 (--all 로 전부 보기)")
        }
        print("")
        // 빠진 게 있다고 실패로 처리하지는 않는다 — 전부 구현할 대상이 아니다.
        // 목록을 보여주는 것이 이 감사의 목적이다.
        return true
    }

    /// 우리 `ItemKind` 가 이 도구를 실제로 다루는가.
    private static func isCovered(slug: String, item: ShowdownItem) -> Bool {
        // 그룹으로 처리하는 것들 — 표가 있으므로 개별 이름을 셀 필요가 없다
        if item.isBerry { return ItemCatalog.kind(for: slug, category: "berries", effect: "") != .none }
        if item.plateType != nil { return true }        // typePlate 표
        if item.megaStone != nil { return true }        // megaStone(effect 파싱)
        if item.zMoveType != nil { return true }        // zCrystalType 표
        if item.isChoice { return true }                // choice(stat:)
        return ItemCatalog.kind(for: slug, category: "held-items", effect: "") != .none
    }

    // MARK: 특성

    private static func auditAbilities(verbose: Bool) -> Bool {
        var missing: [String] = []
        var covered = 0
        var skipped = 0

        for (id, ab) in Showdown.abilities.sorted(by: { $0.key < $1.key }) {
            guard ab.isUsable, ab.hasBattleEffect else { skipped += 1; continue }
            // Showdown 이 쪼개 놓았지만 **PokeAPI 에는 없는** id 는 우리에게
            // 도달할 수 없다 (오거폰의 embodyaspect* 4종). 구현 대상이 아니다.
            guard Showdown.abilityNameByID[id] != nil else { skipped += 1; continue }
            let slug = abilitySlug(id)
            if AbilityCatalog.kind(for: slug) != .none || handledOutsideKind.contains(slug) {
                covered += 1
            }
            else { missing.append(slug) }
        }

        print("-- 특성 --")
        print("  배틀 효과가 있는 특성 \(covered + missing.count)개 중 \(covered)개 구현")
        print("  (효과 없음·과거 세대 \(skipped)개는 제외)")
        if missing.isEmpty {
            print("  ✓ 빠진 특성 없음\n")
            return true
        }
        print("  남은 특성 \(missing.count)개:")
        for slug in (verbose ? missing : Array(missing.prefix(40))) {
            let hooks = Showdown.ability(slug)?.hooks.sorted().joined(separator: ",") ?? ""
            print("    · \(slug)\(hooks.isEmpty ? "" : "  [\(hooks)]")")
        }
        if !verbose, missing.count > 40 {
            print("    … 그 외 \(missing.count - 40)개 (--all 로 전부 보기)")
        }
        print("")
        return true
    }

    // MARK: 내던지기

    /// 내던지기는 **도구마다 위력과 부가효과가 다르다.**
    /// 사용자가 지적한 "내던지기를 하면 상대가 맹독을 입는다" 가 이 표에 있다.
    private static func auditFlingTable(verbose: Bool) -> Bool {
        let flingable = Showdown.items.filter { $0.value.isUsable && $0.value.flingPower != nil }
        let withStatus = flingable.filter {
            $0.value.flingStatus != nil || $0.value.flingVolatile != nil
        }
        print("-- 내던지기 --")
        print("  던질 수 있는 도구 \(flingable.count)개, 그중 부가효과가 붙는 것 \(withStatus.count)개")
        for (id, it) in withStatus.sorted(by: { $0.key < $1.key }) {
            let eff = it.flingStatus ?? it.flingVolatile ?? "?"
            print("    · \(itemSlug(id)) — 위력 \(it.flingPower ?? 0), \(eff)")
        }
        print("")
        return true
    }

    /// Showdown id → PokeAPI slug.
    ///
    /// Showdown 은 하이픈을 지운 소문자 id 를 쓴다("toxicorb"). PokeAPI 는
    /// 하이픈을 쓴다("toxic-orb"). 역변환은 불가능하므로 PokeAPI 쪽 이름 목록을
    /// 미리 만들어 대조한다.
    private static func itemSlug(_ showdownID: String) -> String {
        Showdown.itemNameByID[showdownID] ?? showdownID
    }
    private static func abilitySlug(_ showdownID: String) -> String {
        Showdown.abilityNameByID[showdownID] ?? showdownID
    }

    /// **존재하지 않는 이름을 스위치에 적어두는 실수를 잡는다.**
    ///
    /// PokeAPI slug 은 아포스트로피를 지운다 — "dragons-maw" 이지
    /// "dragon-s-maw" 가 아니다. 오타를 내면 그 case 는 영원히 실행되지
    /// 않고, 우리는 "구현했다" 고 믿는다. 실제로 용의턱이 그랬다.
    static func deadCaseNames() -> (abilities: [String], items: [String]) {
        let realAbilities = Set(Showdown.pokeAPIAbilityNames)
        let realItems = Set(Showdown.pokeAPIItemNames)
        var deadAb: [String] = []
        var deadIt: [String] = []
        for name in switchCaseNames(inFile: "Abilities.swift")
        where !realAbilities.contains(name) { deadAb.append(name) }
        for name in switchCaseNames(inFile: "Items.swift")
        where !realItems.contains(name) { deadIt.append(name) }
        return (deadAb, deadIt)
    }

    /// 소스에서 스위치 case 문자열을 긁어온다.
    /// 소스가 배포본에 없으면(설치된 앱) 빈 배열이라 검사가 조용히 통과한다 —
    /// 개발 중에만 도는 검사다.
    private static func switchCaseNames(inFile file: String) -> [String] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appending(path: "Pokedex").appending(path: file)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [String] = []
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("case \"") else { continue }
            // case "a", "b": ... 형태에서 따옴표 안만 뽑는다
            var parts = t.split(separator: "\"").enumerated()
                .filter { $0.offset % 2 == 1 }
                .map { String($0.element) }
            // 반환값 안의 문자열은 콜론 뒤라 제외한다
            if let colon = t.firstIndex(of: ":") {
                let head = String(t[t.startIndex..<colon])
                parts = head.split(separator: "\"").enumerated()
                    .filter { $0.offset % 2 == 1 }
                    .map { String($0.element) }
            }
            out.append(contentsOf: parts)
        }
        return out
    }

    /// `AbilityKind` 를 거치지 않고 다른 곳에서 처리하는 특성.
    ///
    /// 폼 변화(FormChange)나 개별 분기(Battler.isOblivious)로 구현한 것들은
    /// kind 가 .none 이라 감사에 "빠졌다" 로 잡힌다. 실제로는 동작하므로
    /// 여기 적어 둔다 — 적을 때 반드시 **어디서 처리하는지** 를 남긴다.
    private static let handledOutsideKind: Set<String> = [
        "forecast", "flower-gift", "zen-mode", "schooling",   // FormChange.autoRule
        "oblivious",                                          // Battler.isOblivious
    ]
}
