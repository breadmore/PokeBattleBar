import Foundation

/// `PokeBattleBar --itemtest`
/// PokeAPI 에서 받은 실제 도구 데이터가 배틀 효과로 올바르게 매핑되는지 확인한다.
enum ItemTest {
    static func run() async -> Bool {
        print("=== 지닌 도구 데이터 검증 ===\n")
        print("PokeAPI 에서 도구를 받는 중… (첫 실행은 오래 걸립니다)")
        await ItemCatalog.shared.loadAll()
        let all = await ItemCatalog.shared.items
        var ok = true

        print("  받은 도구: \(all.count)개\n")

        // --- 메가스톤 폼 파싱 ---
        print("-- 메가스톤 → 폼 매핑 --")
        let megaChecks: [(String, String)] = [
            ("charizardite-x", "charizard-mega-x"),
            ("charizardite-y", "charizard-mega-y"),
            ("gengarite",      "gengar-mega"),
            ("alakazite",      "alakazam-mega"),
            ("venusaurite",    "venusaur-mega")
        ]
        for (stone, form) in megaChecks {
            guard let d = all[stone] else { print("  ✗ \(stone) 없음"); ok = false; continue }
            if case .megaStone(let f) = d.kind, f == form {
                print("  ✓ \(d.display) → \(f)")
            } else {
                print("  ✗ \(d.display) → \(d.kind) (기대 \(form))")
                ok = false
            }
        }

        // 파싱 규칙 단위 확인
        let parsed = ItemCatalog.megaForm(fromEffect: "Held: Allows Charizard to Mega Evolve into Mega Charizard X.")
        ok = check(parsed == "charizard-mega-x", "효과 텍스트 파싱", parsed ?? "nil") && ok

        // --- Z크리스탈 타입 매핑: 18타입 전부 ---
        print("\n-- Z크리스탈 → 타입 매핑 (18타입) --")
        var mapped: [PType: String] = [:]
        for d in all.values {
            if case .zCrystalType(let t) = d.kind { mapped[t] = d.name }
        }
        let missing = PType.allCases.filter { mapped[$0] == nil }
        if missing.isEmpty {
            print("  ✓ 18타입 전부 매핑됨")
            for t in [PType.fire, .water, .fighting, .flying, .ice, .dark] {
                print("     \(t.ko) ← \(all[mapped[t]!]?.display ?? mapped[t]!)")
            }
        } else {
            print("  ✗ 누락 타입: \(missing.map(\.ko))")
            ok = false
        }

        // --- 배틀 도구 효과 ---
        print("\n-- 배틀 도구 효과 --")
        let effectChecks: [(String, String)] = [
            ("leftovers", "leftovers"), ("life-orb", "lifeOrb"),
            ("focus-sash", "focusSash"), ("expert-belt", "expertBelt"),
            ("choice-band", "choice"), ("choice-specs", "choice"), ("choice-scarf", "choice"),
            ("eviolite", "eviolite"), ("assault-vest", "assaultVest"),
            ("flame-orb", "selfStatusOrb"), ("toxic-orb", "selfStatusOrb"),
            ("quick-claw", "quickClaw"), ("muscle-band", "classBoost"),
            ("wise-glasses", "classBoost"),
            ("dynamax-band", "dynamaxBand"), ("max-mushrooms", "maxMushroom")
        ]
        for (slug, expect) in effectChecks {
            guard let d = all[slug] else { print("  ✗ \(slug) 없음"); ok = false; continue }
            let desc = "\(d.kind)"
            if desc.contains(expect) {
                print("  ✓ \(d.display.padding(toLength: 12, withPad: " ", startingAt: 0)) \(d.shortEffect.prefix(62))")
            } else {
                print("  ✗ \(d.display) → \(desc) (기대 \(expect))")
                ok = false
            }
        }

        // 구애 계열은 올리는 스탯이 달라야 한다
        for (slug, stat) in [("choice-band", Stat.attack), ("choice-specs", .spAttack), ("choice-scarf", .speed)] {
            if case .choice(let s)? = all[slug]?.kind, s == stat {
                print("  ✓ \(all[slug]!.display) → \(stat.ko) 상승")
            } else { print("  ✗ \(slug) 스탯 매핑 오류"); ok = false }
        }

        // --- 플레이트 ---
        print("\n-- 플레이트 --")
        var plateCount = 0
        for d in all.values { if case .typePlate = d.kind { plateCount += 1 } }
        ok = check(plateCount >= 17, "플레이트 매핑", "\(plateCount)개") && ok

        // --- 종별 지닐 수 있는 도구 ---
        print("\n-- 종별 사용 가능 도구 --")
        for id in [6, 143, 317] {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            let avail = await ItemCatalog.shared.available(forSpecies: sp)
            let stones = avail.filter { if case .megaStone = $0.kind { return true }; return false }
            let mush = avail.contains { if case .maxMushroom = $0.kind { return true }; return false }
            print("  \(sp.display.padding(toLength: 8, withPad: " ", startingAt: 0)) "
                  + "총 \(avail.count)개 / 메가스톤 \(stones.map(\.display)) / 맥스버섯 \(mush ? "O" : "X")")
        }
        // 리자몽은 자기 스톤 2개만, 꿀꺽몬은 0개여야 한다
        if let cha = try? await PokeAPI.shared.species(6) {
            let a = await ItemCatalog.shared.available(forSpecies: cha)
            let stones = a.compactMap { d -> String? in
                if case .megaStone(let f) = d.kind { return f }; return nil
            }.sorted()
            ok = check(stones == ["charizard-mega-x", "charizard-mega-y"],
                       "리자몽은 자기 메가스톤만 보인다", "\(stones)") && ok
        }
        if let swa = try? await PokeAPI.shared.species(317) {
            let a = await ItemCatalog.shared.available(forSpecies: swa)
            let stones = a.filter { if case .megaStone = $0.kind { return true }; return false }
            let mush = a.contains { if case .maxMushroom = $0.kind { return true }; return false }
            ok = check(stones.isEmpty && !mush,
                       "꿀꺽몬은 메가스톤·맥스버섯이 안 보인다", "스톤\(stones.count) 버섯\(mush)") && ok
        }

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func check(_ c: Bool, _ l: String, _ got: String = "") -> Bool {
        print(c ? "  ✓ \(l)" : "  ✗ \(l) — 실제: \(got)")
        return c
    }
}
