import Foundation

/// 실전 세팅(Smogon 분석) 검증.
/// 검증은 **메인 스레드에서** 돌아야 한다 — 배틀 엔진의 한 턴 계산은
/// 디버그 빌드에서 스택 프레임이 커서 협조 스레드(512KB)를 넘긴다.
/// nonisolated async 로 두면 MainActor 에서 불러도 협조 풀로 넘어간다.
@MainActor
enum SmogonSetTest {
    @MainActor
    static func run() async -> Bool {
        print("=== 실전 세팅 ===\n")
        var ok = true
        func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
            print("  \(c ? "✓" : "✗") \(l)\(d.isEmpty ? "" : "  (\(d))")")
            return c
        }

        print("-- 데이터 --")
        ok = show(SmogonSets.speciesCount > 300, "종이 충분히 들어왔다",
                  "\(SmogonSets.speciesCount)종") && ok
        ok = show(SmogonSets.setCount > 1500, "세팅이 충분히 들어왔다",
                  "\(SmogonSets.setCount)개") && ok

        // 도구가 들어 있는가 — 이것이 이 데이터를 쓰는 이유다
        var withItem = 0, total = 0
        for name in ["snorlax", "gengar", "alakazam", "mew", "charizard", "tyranitar"] {
            for s in SmogonSets.sets(forSpeciesName: name) {
                total += 1
                if s.itemID != nil { withItem += 1 }
            }
        }
        ok = show(total > 0 && withItem == total, "세팅마다 도구가 있다",
                  "\(withItem)/\(total)") && ok

        print("\n-- 1대1 포맷이 앞에 온다 --")
        // 우리 배틀이 1대1 이므로 1대1 세팅을 먼저 보여줘야 한다
        var oneVOneFirst = 0, checked = 0
        for name in ["gengar", "alakazam", "snorlax", "mew"] {
            let sets = SmogonSets.sets(forSpeciesName: name)
            guard let first = sets.first, sets.contains(where: { $0.format.contains("1v1") })
            else { continue }
            checked += 1
            if first.format.contains("1v1") { oneVOneFirst += 1 }
        }
        ok = show(checked == 0 || oneVOneFirst == checked, "1대1 세팅이 목록 앞에 온다",
                  "\(oneVOneFirst)/\(checked)") && ok

        print("\n-- 메가스톤·Z크리스탈이 들어 있는가 --")
        var megaSets: [String] = []
        var zSets: [String] = []
        for name in ["charizard", "gengar", "alakazam", "lucario", "salamence",
                     "tyranitar", "scizor", "mawile", "medicham"] {
            for s in SmogonSets.sets(forSpeciesName: name) {
                guard let it = s.itemID else { continue }
                if it.hasSuffix("ite") || it.hasSuffix("ite-x") || it.hasSuffix("ite-y") {
                    megaSets.append("\(name)/\(it)")
                }
                if it.hasSuffix("ium-z") || it.contains("ium-z") {
                    zSets.append("\(name)/\(it)")
                }
            }
        }
        ok = show(!megaSets.isEmpty, "메가스톤 세팅이 있다",
                  megaSets.prefix(3).joined(separator: ", ")) && ok
        if zSets.isEmpty {
            print("  · Z크리스탈 세팅은 표본에 없습니다 (7세대 포맷에만 나옵니다)")
        } else {
            print("  · Z크리스탈 세팅: \(zSets.prefix(3).joined(separator: ", "))")
        }

        print("\n-- 이름 변환 --")
        ok = show(SmogonSets.moveID("Giga Drain") == "giga-drain",
                  "기술 이름을 PokeAPI 형식으로", SmogonSets.moveID("Giga Drain")) && ok
        ok = show(SmogonSets.itemID("Life Orb") == "life-orb", "도구 이름 변환") && ok
        ok = show(SmogonSets.abilityID("Thick Fat") == "thick-fat", "특성 이름 변환") && ok
        ok = show(!SmogonSets.sets(forSpeciesName: "Rotom-Wash").isEmpty
                  || !SmogonSets.sets(forSpeciesName: "rotom-wash").isEmpty,
                  "폼 이름도 찾을 수 있다") && ok

        print("\n-- 팀에서 도구가 겹치지 않는가 --")
        // 같은 종을 여섯 마리 넣으면 예전에는 전원이 같은 도구를 들었다
        let m = AppModel()
        let ids = [143, 143, 143, 94, 94, 65]
        m.roster = ids.enumerated().map { i, id in
            RosterSlot(id: "s\(i)", speciesID: id, nature: "serious", rarity: "common",
                       isShiny: false, origin: .dex, fullyEvolved: true)
        }
        m.rules.maxTeamSize = 6
        m.selectedSlotIDs = Set(m.roster.map(\.id))
        await ItemCatalog.shared.loadAll()
        for id in Set(ids) {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            m.rosterSpecies[id] = sp
            m.itemsForSpecies[id] = await ItemCatalog.shared.available(forSpecies: sp)
            m.abilitiesForSpecies[id] = await AbilityCatalog.shared.abilities(for: sp)
        }

        let applied = await m.applyRecommendationToTeam()
        var items: [String] = []
        var slots: [String] = []
        for slot in m.teamSlots {
            guard let n = m.loadouts[slot.id]?.item else { continue }
            items.append(n)
            if let it = (m.itemsForSpecies[slot.speciesID] ?? []).first(where: { $0.name == n }),
               let s = it.transformSlot { slots.append(s) }
        }
        print("  적용 \(applied)마리 / 도구: \(items.joined(separator: ", "))")
        ok = show(items.count == Set(items).count, "같은 도구를 두 마리가 들지 않는다",
                  "\(items.count)개 중 서로 다른 것 \(Set(items).count)개") && ok
        ok = show(slots.count == Set(slots).count,
                  "변신 슬롯(메가·다이맥스·Z)이 겹치지 않는다",
                  slots.isEmpty ? "변신 도구 없음" : slots.joined(separator: ", ")) && ok

        print("\n-- 세팅 적용이 성격을 건드리지 않는가 --")
        // 성격은 PokeTokenBar 를 따라야 한다 — 세팅에는 성격을 아예 담지 않았다
        let before = m.roster.map(\.nature)
        if let slot = m.roster.first, let set = m.smogonSets(for: slot).first {
            _ = await m.applySmogonSet(set, to: slot)
        }
        ok = show(m.roster.map(\.nature) == before, "성격이 그대로다",
                  "\(Set(before))") && ok

        // 사용자 제보: "실전추천하면 z기술이 미반영 된대"
        //
        // Z크리스탈은 PokeAPI 가 "electrium-z--held" 로 주는데 세팅은
        // "Electrium Z" 로 적는다. 이름이 어긋나면 도구가 **조용히** 안 붙는다.
        print("\n-- Z크리스탈 세팅이 실제로 붙는가 --")
        var zCount = 0, zResolved = 0
        var missing: [String] = []
        for (speciesName, sets) in SmogonSets.allByCatalog {
            for set in sets {
                guard let want = set.itemID, want.hasSuffix("-z") else { continue }
                zCount += 1
                if await ItemCatalog.shared.item(want) != nil {
                    zResolved += 1
                } else if missing.count < 8 {
                    missing.append("\(speciesName)/\(set.name): \(want)")
                }
            }
        }
        ok = show(zCount > 0, "Z크리스탈 세팅이 데이터에 있다", "\(zCount)개") && ok
        ok = show(zResolved == zCount, "Z크리스탈 이름이 모두 카탈로그에 있다",
                  missing.isEmpty ? "\(zResolved)/\(zCount)"
                                  : "못 찾음: \(missing.joined(separator: ", "))") && ok

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }
}
