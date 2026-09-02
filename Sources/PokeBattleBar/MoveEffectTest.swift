import Foundation

/// `PokeBattleBar --movetest`
/// 기술 부가효과를 하나씩 **실제로 굴려서** 의도대로 작동하는지 확인한다.
/// PokeAPI 는 자폭처럼 구조화되지 않은 효과가 있어서, 눈으로 코드를 읽는 것으로는 부족하다.
enum MoveEffectTest {

    static func run(verbose: Bool) async -> Bool {
        print("=== 기술 효과 전수 점검 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else {
            print("✗ 상성표 로드 실패"); return false
        }

        var ok = true
        var checked = 0

        // MARK: 반동 / 흡수 / 회복
        ok = await assert("double-edge", "반동 데미지로 쓴 쪽 HP 감소", chart, verbose) { before, after, _ in
            after.att.currentHP < before.att.currentHP
        } && ok; checked += 1

        ok = await assert("giga-drain", "흡수로 쓴 쪽 HP 회복", chart, verbose,
                          setup: { s in s.att.currentHP = s.att.maxHP / 2 }) { before, after, _ in
            after.att.currentHP > before.att.currentHP
        } && ok; checked += 1

        ok = await assert("recover", "회복기로 HP 회복", chart, verbose,
                          setup: { s in s.att.currentHP = s.att.maxHP / 3 }) { before, after, _ in
            after.att.currentHP > before.att.currentHP
        } && ok; checked += 1

        ok = await assert("absorb", "소량 흡수", chart, verbose,
                          setup: { s in s.att.currentHP = s.att.maxHP / 2 }) { before, after, _ in
            after.att.currentHP > before.att.currentHP
        } && ok; checked += 1

        // MARK: 상태이상
        ok = await assert("thunder-wave", "마비 부여", chart, verbose) { _, after, _ in
            after.def.status == .paralysis
        } && ok; checked += 1

        ok = await assert("will-o-wisp", "화상 부여", chart, verbose) { _, after, _ in
            after.def.status == .burn
        } && ok; checked += 1

        ok = await assert("toxic", "맹독 부여", chart, verbose) { _, after, _ in
            after.def.status == .toxic && after.def.toxicCounter > 0
        } && ok; checked += 1

        ok = await assert("poison-powder", "독 부여", chart, verbose) { _, after, _ in
            after.def.status == .poison
        } && ok; checked += 1

        ok = await assert("sleep-powder", "잠듦 부여", chart, verbose) { _, after, _ in
            after.def.status == .sleep && after.def.sleepTurns > 0
        } && ok; checked += 1

        ok = await assert("confuse-ray", "혼란 부여", chart, verbose) { _, after, _ in
            after.def.confusionTurns > 0
        } && ok; checked += 1

        // MARK: 상태이상 타입 면역
        ok = await assert("will-o-wisp", "불꽃 타입은 화상 면역", chart, verbose,
                          defenderSpecies: 6) { _, after, _ in     // 리자몽 (불꽃/비행)
            after.def.status == .none
        } && ok; checked += 1

        ok = await assert("toxic", "강철 타입은 독 면역", chart, verbose,
                          defenderSpecies: 208) { _, after, _ in   // 강철톤 (강철/땅)
            after.def.status == .none
        } && ok; checked += 1

        // MARK: 능력치 랭크
        ok = await assert("swords-dance", "자신 공격 +2", chart, verbose) { _, after, _ in
            (after.att.stages[.attack] ?? 0) == 2
        } && ok; checked += 1

        ok = await assert("growl", "상대 공격 -1", chart, verbose) { _, after, _ in
            (after.def.stages[.attack] ?? 0) == -1
        } && ok; checked += 1

        ok = await assert("string-shot", "상대 스피드 하락", chart, verbose) { _, after, _ in
            (after.def.stages[.speed] ?? 0) < 0
        } && ok; checked += 1

        ok = await assert("calm-mind", "자신 특공·특방 상승", chart, verbose) { _, after, _ in
            (after.att.stages[.spAttack] ?? 0) > 0 && (after.att.stages[.spDefense] ?? 0) > 0
        } && ok; checked += 1

        // MARK: 다단히트
        ok = await assert("double-slap", "다단히트 (로그에 'N번 맞았다')", chart, verbose) { _, _, log in
            log.contains { $0.contains("번 맞았다") }
        } && ok; checked += 1

        // MARK: 고정 데미지
        ok = await assert("dragon-rage", "고정 40 데미지", chart, verbose) { before, after, _ in
            before.def.currentHP - after.def.currentHP == 40
        } && ok; checked += 1

        ok = await assert("sonic-boom", "고정 20 데미지", chart, verbose) { before, after, _ in
            before.def.currentHP - after.def.currentHP == 20
        } && ok; checked += 1

        // 나이트헤드는 고스트 타입 — 노말(잠만보) 에게는 원래 0배다.
        // 상성을 받는 상대(리자몽)로 확인한다.
        ok = await assert("night-shade", "레벨만큼 데미지 (Lv.50 → 50)", chart, verbose,
                          defenderSpecies: 6) { before, after, _ in
            before.def.currentHP - after.def.currentHP == 50
        } && ok; checked += 1

        ok = await assert("night-shade", "고스트 기술은 노말에게 무효", chart, verbose,
                          defenderSpecies: 143) { before, after, _ in
            before.def.currentHP == after.def.currentHP
        } && ok; checked += 1

        ok = await assert("seismic-toss", "레벨만큼 데미지", chart, verbose) { before, after, _ in
            before.def.currentHP - after.def.currentHP == 50
        } && ok; checked += 1

        // MARK: 자폭
        ok = await assert("explosion", "대폭발 — 쓴 쪽이 쓰러진다", chart, verbose) { _, after, _ in
            after.att.isFainted
        } && ok; checked += 1

        ok = await assert("self-destruct", "자폭 — 쓴 쪽이 쓰러진다", chart, verbose) { _, after, _ in
            after.att.isFainted
        } && ok; checked += 1

        ok = await assert("final-gambit", "목숨걸기 — 내 HP만큼 주고 쓰러진다", chart, verbose) { before, after, _ in
            after.att.isFainted && (before.def.currentHP - after.def.currentHP) == before.att.currentHP
        } && ok; checked += 1

        ok = await assert("memento", "메멘토 — 쓴 쪽이 쓰러진다", chart, verbose) { _, after, _ in
            after.att.isFainted
        } && ok; checked += 1

        // MARK: 풀죽음
        // 풀죽음은 같은 턴에 적용되고 바로 소비된다 (그게 정상) — 로그로 확인한다.
        ok = await assert("fake-out", "풀죽음으로 상대 행동 봉쇄", chart, verbose) { _, _, log in
            log.contains { $0.contains("풀이 죽어") }
        } && ok; checked += 1

        // MARK: 필중기
        ok = await assert("swift", "필중기는 빗나가지 않는다", chart, verbose, seeds: 30) { before, after, log in
            before.def.currentHP > after.def.currentHP && !log.contains { $0.contains("빗나갔다") }
        } && ok; checked += 1

        // MARK: 턴 종료 지속 데미지
        print("\n  -- 턴 종료 지속 데미지 --")
        ok = await residualCheck("독", chart, status: .poison, verbose: verbose) && ok; checked += 1
        ok = await residualCheck("화상", chart, status: .burn, verbose: verbose) && ok; checked += 1
        ok = await residualCheck("맹독", chart, status: .toxic, verbose: verbose) && ok; checked += 1
        ok = await toxicEscalates(chart) && ok; checked += 1

        print("\n\(checked)개 항목 점검")
        print(ok ? "✓ 전부 통과" : "✗ 실패 항목 있음")
        return ok
    }

    // MARK: 시나리오 실행

    struct Snapshot { var att: Battler; var def: Battler }

    /// 공격측이 반드시 먼저 움직이는 1대1 상황을 만들어 기술 하나를 쓴다.
    /// 확률 효과가 있으므로 여러 시드를 돌려 **한 번이라도** 성립하면 통과로 본다.
    private static func assert(
        _ moveName: String,
        _ label: String,
        _ chart: TypeChart,
        _ verbose: Bool,
        attackerSpecies: Int = 143,     // 잠만보 — HP 가 커서 관찰이 쉽다
        defenderSpecies: Int = 143,
        seeds: Int = 24,
        setup: ((inout Snapshot) -> Void)? = nil,
        _ predicate: @escaping (Snapshot, Snapshot, [String]) -> Bool
    ) async -> Bool {
        guard let move = try? await PokeAPI.shared.move(moveName),
              let splash = try? await PokeAPI.shared.move("splash"),
              let attSpec = try? await PokeAPI.shared.species(attackerSpecies),
              let defSpec = try? await PokeAPI.shared.species(defenderSpecies) else {
            print("  ✗ \(label) — \(moveName) 데이터 로드 실패")
            return false
        }

        var lastLog: [String] = []
        for seed in 1...seeds {
            var att = battler(attSpec, moves: [move], id: "att")
            var def = battler(defSpec, moves: [splash], id: "def")
            att.stats[.speed] = 999          // 항상 선공하게 고정
            def.stats[.speed] = 1

            var snap = Snapshot(att: att, def: def)
            setup?(&snap)
            att = snap.att; def = snap.def

            var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                                 sides: [SideState(playerName: "A", team: [att], activeIndex: 0),
                                         SideState(playerName: "B", team: [def], activeIndex: 0)])
            st.phase = .awaitingMoves
            st.turn = 1
            var e = BattleEngine(state: st, chart: chart, seed: UInt64(seed) * 7919)

            let before = Snapshot(att: att, def: def)
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            let after = Snapshot(att: e.state.sides[0].team[0], def: e.state.sides[1].team[0])
            lastLog = e.state.log

            if predicate(before, after, e.state.log) {
                print("  ✓ \(label)")
                if verbose { for l in e.state.log { print("      \(l)") } }
                return true
            }
        }
        print("  ✗ \(label)  [\(moveName)] — 시드 \(seeds)회 모두 실패")
        for l in lastLog.prefix(8) { print("      \(l)") }
        return false
    }

    /// 상태이상 지속 데미지가 턴 종료에 실제로 들어가는지
    private static func residualCheck(_ label: String, _ chart: TypeChart,
                                      status: Ailment, verbose: Bool) async -> Bool {
        guard let splash = try? await PokeAPI.shared.move("splash"),
              let spec = try? await PokeAPI.shared.species(143) else { return false }

        var att = battler(spec, moves: [splash], id: "att")
        var def = battler(spec, moves: [splash], id: "def")
        def.status = status
        if status == .toxic { def.toxicCounter = 1 }
        let hpBefore = def.currentHP
        att.stats[.speed] = 999; def.stats[.speed] = 1

        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "A", team: [att], activeIndex: 0),
                                     SideState(playerName: "B", team: [def], activeIndex: 0)])
        st.phase = .awaitingMoves
        var e = BattleEngine(state: st, chart: chart, seed: 12345)
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let hpAfter = e.state.sides[1].team[0].currentHP

        if hpAfter < hpBefore {
            print("  ✓ \(label) 지속 데미지 (\(hpBefore) → \(hpAfter))")
            return true
        }
        print("  ✗ \(label) 지속 데미지가 들어가지 않았다 (\(hpBefore) → \(hpAfter))")
        return false
    }

    /// 맹독은 턴마다 데미지가 커져야 한다 (1/16, 2/16, 3/16 …).
    /// 일반 독으로 잘못 걸리면 매 턴 같은 값이라 여기서 잡힌다.
    private static func toxicEscalates(_ chart: TypeChart) async -> Bool {
        guard let splash = try? await PokeAPI.shared.move("splash"),
              let spec = try? await PokeAPI.shared.species(143) else { return false }
        var att = battler(spec, moves: [splash], id: "att")
        var def = battler(spec, moves: [splash], id: "def")
        def.status = .toxic; def.toxicCounter = 1
        att.stats[.speed] = 999; def.stats[.speed] = 1

        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "A", team: [att], activeIndex: 0),
                                     SideState(playerName: "B", team: [def], activeIndex: 0)])
        st.phase = .awaitingMoves
        var e = BattleEngine(state: st, chart: chart, seed: 999)

        var deltas: [Int] = []
        for _ in 0..<3 {
            guard case .awaitingMoves = e.state.phase else { break }
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            deltas.append(before - e.state.sides[1].team[0].currentHP)
        }
        let escalating = deltas.count >= 3 && deltas[1] > deltas[0] && deltas[2] > deltas[1]
        print(escalating ? "  ✓ 맹독 데미지 누적 증가 \(deltas)"
                         : "  ✗ 맹독이 누적 증가하지 않는다 \(deltas) — 일반 독으로 걸렸을 가능성")
        return escalating
    }

    private static func battler(_ sp: SpeciesDef, moves: [MoveDef], id: String) -> Battler {
        let slot = RosterSlot(id: id, speciesID: sp.id, nature: "serious",
                              rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
        return Battler.make(slot: slot, species: sp, moves: moves, level: 50)
    }
}
