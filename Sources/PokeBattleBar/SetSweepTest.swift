import Foundation

/// **모든 실전 세팅을 한 번씩** 훑어 데이터가 온전한지 본다.
///
/// 세팅은 2,400개가 넘는다. 손으로 확인할 수 없으니 전부 돌려서
/// 이름이 안 풀리는 기술·도구·특성, 위력이 0 이 되는 기술을 찾아낸다.
enum SetSweepTest {

    static func run(limitSpecies: Int, verbose: Bool) async -> Bool {
        print("=== 실전 세팅 전수 점검 ===\n")
        var ok = true
        func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
            print("  \(c ? "✓" : "✗") \(l)\(d.isEmpty ? "" : "  (\(d))")")
            return c
        }

        await ItemCatalog.shared.loadAll()

        // #649 이하만 본다 — PokeTokenBar 가 그 위 종을 주지 않는다
        var speciesIDs: [Int] = []
        for id in 1...649 { speciesIDs.append(id) }
        if limitSpecies > 0 { speciesIDs = Array(speciesIDs.prefix(limitSpecies)) }

        var checkedSpecies = 0, checkedSets = 0
        var unknownMoves: Set<String> = []
        var unknownItems: Set<String> = []
        var unknownAbilities: Set<String> = []
        var zeroPowerMoves: Set<String> = []
        var setsWithNoMove: [String] = []
        var setsWithNoItem: [String] = []

        for id in speciesIDs {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            let sets = SmogonSets.sets(forSpeciesName: sp.name)
            guard !sets.isEmpty else { continue }
            checkedSpecies += 1

            let learnable = Set(sp.learnableMoves)
            let avail = await ItemCatalog.shared.available(forSpecies: sp)
            let availNames = Set(avail.map(\.name))
            let abils = Set(sp.abilitySlots.map(\.name))

            for set in sets {
                checkedSets += 1

                // 기술 — 이름이 PokeAPI 에서 풀리는가, 위력이 0 이 아닌가
                var applicable = 0
                for opts in set.allMoveOptions {
                    for mid in opts {
                        guard learnable.contains(mid) else { continue }
                        applicable += 1
                        guard let mv = try? await PokeAPI.shared.move(mid) else {
                            unknownMoves.insert(mid); continue
                        }
                        // 공격기인데 위력이 0 이면 아무 데미지도 안 들어간다
                        if mv.damageClass != .status, mv.specialDamage == .none,
                           (mv.power ?? 0) == 0,
                           MoveFlags.isCharge(mid) == false {
                            zeroPowerMoves.insert("\(mv.display)(\(mid))")
                        }
                    }
                }
                if applicable == 0 {
                    setsWithNoMove.append("\(sp.display)/\(set.name)")
                }

                // 도구
                if let want = set.itemID {
                    if await ItemCatalog.shared.item(want) == nil {
                        unknownItems.insert(want)
                    } else if !availNames.contains(want) {
                        setsWithNoItem.append("\(sp.display)/\(set.name)/\(want)")
                    }
                }

                // 특성
                if let want = set.abilityID, !abils.contains(want) {
                    unknownAbilities.insert("\(sp.display)/\(want)")
                }
            }
        }

        print("  점검한 종 \(checkedSpecies)개 / 세팅 \(checkedSets)개\n")
        ok = show(checkedSets > 200, "세팅을 충분히 돌렸다", "\(checkedSets)개") && ok

        print("-- 이름이 풀리지 않는 항목 --")
        ok = show(unknownMoves.isEmpty, "모든 기술 이름이 PokeAPI 에서 풀린다",
                  unknownMoves.isEmpty ? "" : "\(unknownMoves.sorted().prefix(10))") && ok
        ok = show(unknownItems.isEmpty, "모든 도구 이름이 우리 목록에 있다",
                  unknownItems.isEmpty ? "" : "\(unknownItems.sorted().prefix(10))") && ok

        print("\n-- 위력이 0 이 되는 공격기 --")
        if zeroPowerMoves.isEmpty {
            print("  없음")
        } else {
            for m in zeroPowerMoves.sorted() { print("  · \(m)") }
        }
        ok = show(zeroPowerMoves.isEmpty,
                  "세팅에 실린 공격기는 모두 위력이 있다",
                  "\(zeroPowerMoves.count)개") && ok

        print("\n-- 적용할 수 있는 기술이 하나도 없는 세팅 --")
        // 다른 세대 전용 기술로만 짜인 세팅은 걸러져야 한다
        if setsWithNoMove.isEmpty { print("  없음") }
        else {
            for x in setsWithNoMove.prefix(10) { print("  · \(x)") }
            print("  총 \(setsWithNoMove.count)개 — 이 세팅은 목록에서 걸러진다")
        }

        print("\n-- 도구가 그 종에게 노출되지 않는 세팅 --")
        if setsWithNoItem.isEmpty { print("  없음") }
        else {
            for x in setsWithNoItem.prefix(10) { print("  · \(x)") }
            print("  총 \(setsWithNoItem.count)개 — 적용할 때 다른 도구로 바뀐다")
        }

        if !unknownAbilities.isEmpty && verbose {
            print("\n-- 그 종이 가질 수 없는 특성을 지정한 세팅 --")
            for x in unknownAbilities.sorted().prefix(15) { print("  · \(x)") }
            print("  총 \(unknownAbilities.count)개 (다른 세대 특성 — 적용에서 건너뛴다)")
        }

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }
}
