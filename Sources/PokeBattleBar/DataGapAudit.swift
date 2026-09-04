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
        return ok
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
