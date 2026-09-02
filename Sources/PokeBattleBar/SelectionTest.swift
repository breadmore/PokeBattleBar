import Foundation

/// `PokeBattleBar --pickertest`
/// "내가 고른 포켓몬이 아니라 맨 왼쪽이 나온다" 회귀 방지 테스트.
enum SelectionTest {

    @MainActor
    static func run() async -> Bool {
        print("=== 포켓몬 선택 검증 ===\n")
        var ok = true

        // 도감 6마리를 가진 상황을 만든다
        let ids = [87, 317, 143, 130, 149, 94]
        let roster = ids.enumerated().map { i, id in
            RosterSlot(id: "slot-\(i)", speciesID: id, nature: "bold",
                       rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
        }

        // --- A) 부분 선택을 존중하는가 (예전엔 개수가 정원과 다르면 왼쪽부터 채웠다) ---
        let m = AppModel()
        m.roster = roster
        m.rules.maxTeamSize = 6
        // 6마리 중 3번·5번·6번째만 고른다
        m.selectedSlotIDs = ["slot-2", "slot-4", "slot-5"]
        let picked = m.teamSlots.map(\.id)
        ok = check(picked == ["slot-2", "slot-4", "slot-5"],
                   "부분 선택(3/6) 존중", got: "\(picked)") && ok

        // --- B) 상한이 줄어도 고른 것을 유지하는가 (덮어쓰지 않는가) ---
        m.rules.maxTeamSize = 2
        m.trimSelectionToCap()
        let trimmed = m.teamSlots.map(\.id)
        ok = check(trimmed == ["slot-2", "slot-4"],
                   "상한 축소 시 고른 것 중에서 다듬기", got: "\(trimmed)") && ok
        ok = check(!trimmed.contains("slot-0"),
                   "상한 축소가 맨 왼쪽으로 리셋하지 않음", got: "\(trimmed)") && ok

        // --- C) 선택이 비어 있으면 왼쪽부터 (합리적 기본값) ---
        m.rules.maxTeamSize = 3
        m.selectedSlotIDs = []
        let fallback = m.teamSlots.map(\.id)
        ok = check(fallback == ["slot-0", "slot-1", "slot-2"],
                   "선택이 없으면 앞에서 3마리", got: "\(fallback)") && ok

        // --- D) 엔진이 고른 선봉을 실제로 내보내는가 ---
        guard let chart = try? await PokeAPI.shared.typeChart(),
              let teamA = await team(ids, tag: "A"),
              let teamB = await team(ids, tag: "B") else {
            print("✗ 팀/상성표 준비 실패")
            return false
        }

        var st = BattleState(rules: BattleRules(maxTeamSize: 6, level: 50),
                             sides: [SideState(playerName: "A", team: teamA, activeIndex: 0),
                                     SideState(playerName: "B", team: teamB, activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 42)
        e.setLead(.host, index: 4)     // 5번째
        e.setLead(.guest, index: 2)    // 3번째
        e.beginBattle()

        ok = check(e.state.sides[0].activeIndex == 4,
                   "호스트 선봉 = 고른 5번째", got: "\(e.state.sides[0].activeIndex)") && ok
        ok = check(e.state.sides[1].activeIndex == 2,
                   "게스트 선봉 = 고른 3번째", got: "\(e.state.sides[1].activeIndex)") && ok
        ok = check(e.state.side(.host).active.id == teamA[4].id,
                   "실제로 나온 개체가 고른 개체", got: e.state.side(.host).active.name) && ok
        ok = check(!e.state.log.contains(where: { $0.contains("[경고]") }),
                   "정상 인덱스에는 경고 없음") && ok

        // --- E) 교체 인덱스도 존중하는가 ---
        var e2 = e
        e2.state.sides[0].team[4].currentHP = 0            // 선봉을 쓰러뜨린다
        e2.state.phase = .awaitingReplacement([0])
        e2.applyReplacement(.host, teamIndex: 5)           // 6번째를 낸다
        ok = check(e2.state.sides[0].activeIndex == 5,
                   "교체 = 고른 6번째", got: "\(e2.state.sides[0].activeIndex)") && ok

        // --- F) 범위를 벗어난 인덱스가 조용히 0 이 되지 않는가 (버그의 정체) ---
        var e3 = BattleEngine(state: st, chart: chart, seed: 42)
        e3.setLead(.host, index: 99)
        let warned = e3.state.log.contains { $0.contains("[경고]") }
        ok = check(warned, "범위 초과 인덱스는 경고를 남긴다 (조용한 실패 금지)") && ok
        ok = check(e3.state.sides[0].activeIndex == teamA.count - 1,
                   "범위 초과는 클램프 (0 으로 떨어지지 않음)",
                   got: "\(e3.state.sides[0].activeIndex)") && ok

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func check(_ cond: Bool, _ label: String, got: String? = nil) -> Bool {
        if cond { print("  ✓ \(label)"); return true }
        print("  ✗ \(label)" + (got.map { " — 실제: \($0)" } ?? ""))
        return false
    }

    private static func team(_ ids: [Int], tag: String) async -> [Battler]? {
        var out: [Battler] = []
        for (i, id) in ids.enumerated() {
            guard let sp = try? await PokeAPI.shared.species(id) else { return nil }
            let slot = RosterSlot(id: "\(tag)-\(i)", speciesID: id, nature: "bold",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            let moves = await MovesetStore.shared.moveset(for: slot, species: sp)
            guard !moves.isEmpty else { return nil }
            out.append(Battler.make(slot: slot, species: sp, moves: moves, level: 50))
        }
        return out
    }
}
