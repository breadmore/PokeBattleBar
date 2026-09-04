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
        return ok
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
            let slug = pokeAPISlug(id)
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
            let slug = pokeAPISlug(id)
            if AbilityCatalog.kind(for: slug) != .none { covered += 1 }
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
            print("    · \(pokeAPISlug(id)) — 위력 \(it.flingPower ?? 0), \(eff)")
        }
        print("")
        return true
    }

    /// Showdown id → PokeAPI slug.
    ///
    /// Showdown 은 하이픈을 지운 소문자 id 를 쓴다("toxicorb"). PokeAPI 는
    /// 하이픈을 쓴다("toxic-orb"). 역변환은 불가능하므로 PokeAPI 쪽 이름 목록을
    /// 미리 만들어 대조한다.
    private static func pokeAPISlug(_ showdownID: String) -> String {
        slugIndex[showdownID] ?? showdownID
    }

    /// 우리가 이름을 아는 도구·특성 slug 를 Showdown id 로 색인해 둔다.
    private static let slugIndex: [String: String] = {
        // Showdown id("toxicorb") → PokeAPI slug("toxic-orb").
        //
        // 역변환은 불가능하므로 **우리가 표로 알고 있는 이름**을 색인해 둔다.
        // 여기 없는 것은 id 그대로 보여준다 (구현 안 된 것들이라 어차피 그렇다).
        var out: [String: String] = [:]
        for slug in ItemCatalog.allKnownSlugs {
            out[Showdown.id(fromPokeAPI: slug)] = slug
        }
        return out
    }()
}
