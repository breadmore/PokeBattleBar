import Foundation

/// **모든 실전 세팅을 한 번씩** 훑어 데이터가 온전한지 본다.
///
/// 세팅은 2,400개가 넘는다. 손으로 확인할 수 없으니 전부 돌려서
/// 이름이 안 풀리는 기술·도구·특성, 위력이 0 이 되는 기술을 찾아낸다.
/// 검증은 **메인 스레드에서** 돌아야 한다 — 배틀 엔진의 한 턴 계산은
/// 디버그 빌드에서 스택 프레임이 커서 협조 스레드(512KB)를 넘긴다.
/// nonisolated async 로 두면 MainActor 에서 불러도 협조 풀로 넘어간다.
@MainActor
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
                        // 공격기인데 **아무 데미지도 못 넣는가.**
                        //
                        // 원시 `power` 만 보면 오탐이 난다 — 위력이 nil 이어도
                        // 실제로는 데미지가 들어가는 기술이 있다:
                        //   · 카운터·미러코트 — 받은 데미지의 두 배
                        //   · 풀묶기·안다리걸기 — 상대 무게로 위력이 정해진다
                        //   · 자이로볼·은혜갚기 — 상황으로 위력이 정해진다
                        //   · 일격필살 — 위력 개념이 없다
                        // `isDamaging` 이 이 경우를 모두 본다. 오탐이 섞이면
                        // "빠진 기술 찾기" 라는 이 검사의 목적이 흐려진다.
                        if mv.damageClass != .status, !mv.isDamaging,
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
        // **PokeAPI 가 모르는 이름은 실패가 아니다.**
        //
        // 2세대 세팅에는 mint-berry·miracle-berry 처럼 3세대에 개명된 이름이
        // 남아 있다 (지금은 리샘·유루열매다). 존재하지 않는 도구를 목록에
        // 넣을 수는 없으므로 "해당 없음" 으로 가른다 — 섞어두면 진짜 구멍이
        // 가려진다.
        let known = Set(Showdown.pokeAPIItemNames)
        let gone = unknownItems.filter { !known.contains($0) }.sorted()
        let realGaps = unknownItems.filter { known.contains($0) }.sorted()
        if !gone.isEmpty {
            print("  · 지금은 없는 옛 이름 \(gone.count)개 (해당 없음): "
                  + gone.joined(separator: ", "))
        }
        ok = show(realGaps.isEmpty, "실제로 존재하는 도구는 모두 우리 목록에 있다",
                  realGaps.isEmpty ? "" : "\(realGaps.prefix(10))") && ok

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
