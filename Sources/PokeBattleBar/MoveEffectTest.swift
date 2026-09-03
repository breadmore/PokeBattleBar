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

        // 이상한빛은 고스트 타입 — 노말(잠만보)에게는 무효다. 상성을 받는 상대로 확인한다.
        ok = await assert("confuse-ray", "혼란 부여", chart, verbose,
                          defenderSpecies: 6) { _, after, _ in     // 리자몽
            after.def.confusionTurns > 0
        } && ok; checked += 1
        ok = await assert("confuse-ray", "고스트 변화기는 노말에게 무효", chart, verbose,
                          defenderSpecies: 143) { _, after, _ in
            after.def.confusionTurns == 0
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

        // MARK: 묶기 기술 (지속 데미지)
        print("\n-- 묶기 기술 (지속 데미지) --")
        for (mv, label) in [("whirlpool", "바다회오리"), ("fire-spin", "회오리불꽃"),
                            ("bind", "조이기"), ("infestation", "엉겨붙기"),
                            ("sand-tomb", "모래지옥"), ("magma-storm", "마그마스톰")] {
            ok = await trapCheck(mv, label, chart) && ok; checked += 1
        }
        ok = await trapDoesNotStack(chart) && ok; checked += 1

        // MARK: 유턴 계열
        print("\n-- 유턴 계열 (쓴 뒤 물러난다) --")
        for (mv, label) in [("u-turn", "유턴"), ("volt-switch", "볼트체인지"),
                            ("flip-turn", "퀵턴")] {
            ok = await pivotCheck(mv, label, chart) && ok; checked += 1
        }

        // MARK: 상태이상이 만드는 부가 효과 전수 점검
        print("\n-- 상태이상 부가 효과 --")
        ok = await statusSideEffects(chart, &checked) && ok

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

    /// 묶기 기술이 붙잡고 턴마다 피해를 주는가
    private static func trapCheck(_ move: String, _ label: String,
                                  _ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: [move], defMoves: ["splash"],
                                           chart: chart, seed: 8291) else {
            print("  ✗ \(label) — 준비 실패"); return false
        }
        e.state.sides[1].team[0].maxHP = 99999
        e.state.sides[1].team[0].currentHP = 99999

        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let trapped = e.state.sides[1].team[0].trappedTurns
        let bound = e.state.log.contains { $0.contains("붙잡혔다") }
        guard trapped > 0, bound else {
            print("  ✗ \(label) — 붙잡지 못했다 (turns=\(trapped))")
            for l in e.state.log.prefix(5) { print("      \(l)") }
            return false
        }

        // 다음 턴에 공격을 안 해도 지속 피해가 들어가야 한다
        let hpBefore = e.state.sides[1].team[0].currentHP
        guard case .awaitingMoves = e.state.phase else {
            print("  ✗ \(label) — 다음 턴으로 못 감"); return false
        }
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let hpAfter = e.state.sides[1].team[0].currentHP
        let residual = e.state.log.contains { $0.contains("시달리고 있다") }
        let pass = hpAfter < hpBefore && residual
        print(pass ? "  ✓ \(label) — \(trapped)턴 묶고 지속 피해 (\(hpBefore - hpAfter))"
                   : "  ✗ \(label) — 지속 피해 없음 (\(hpBefore) → \(hpAfter))")
        return pass
    }

    /// 이미 묶인 상대에게 또 걸어도 턴수가 겹쳐 늘어나지 않는다
    /// 이미 묶인 상대에게 다시 걸어도 턴수가 늘어나지 않는다.
    /// 바다회오리는 명중 85 라 빗나갈 수 있다 — 첫 타격이 **실제로 명중한 시드**에서만 판정한다.
    private static func trapDoesNotStack(_ chart: TypeChart) async -> Bool {
        for seed in 1...40 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["whirlpool"], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 97) else { return false }
            e.state.sides[1].team[0].maxHP = 999999
            e.state.sides[1].team[0].currentHP = 999999
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            let first = e.state.sides[1].team[0].trappedTurns
            guard first > 0 else { continue }        // 빗나갔으면 다음 시드

            guard case .awaitingMoves = e.state.phase else { continue }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            let second = e.state.sides[1].team[0].trappedTurns
            // 두 번째 사용은 새로 걸리지 않으므로 턴수가 1 줄어야 한다
            let pass = second == first - 1
            print(pass ? "  ✓ 묶기는 중첩되지 않는다 (남은 \(first)턴 → \(second)턴)"
                       : "  ✗ 묶기가 중첩됐다 (\(first) → \(second), 기대 \(first - 1))")
            return pass
        }
        print("  ✗ 묶기 중첩 — 40시드 모두 첫 타격이 빗나갔다")
        return false
    }

    /// 유턴 계열을 쓰면 자신이 물러나는 단계로 넘어가는가
    private static func pivotCheck(_ move: String, _ label: String,
                                   _ chart: TypeChart) async -> Bool {
        guard let sp = try? await PokeAPI.shared.species(143),
              let mv = try? await PokeAPI.shared.move(move),
              let splash = try? await PokeAPI.shared.move("splash") else {
            print("  ✗ \(label) — 준비 실패"); return false
        }
        func mk(_ tag: String, _ m: [MoveDef]) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: 143, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: m, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.maxHP = 99999; b.currentHP = 99999
            return b
        }
        var a1 = mk("a1", [mv]); a1.stats[.speed] = 999
        let a2 = mk("a2", [splash])
        var d = mk("b", [splash]); d.stats[.speed] = 1

        var rules = BattleRules(maxTeamSize: 6, level: 50)
        rules.requireItems = false
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: [a1, a2], activeIndex: 0),
                                     SideState(playerName: "B", team: [d], activeIndex: 0)])
        st.phase = .awaitingMoves
        st.turn = 1
        var e = BattleEngine(state: st, chart: chart, seed: 4747)
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))

        guard case .awaitingPivot(let pending) = e.state.phase, pending.contains(0) else {
            print("  ✗ \(label) — 물러나는 단계로 가지 않았다 (phase=\(e.state.phase))")
            for l in e.state.log.prefix(5) { print("      \(l)") }
            return false
        }
        e.applyPivot(.host, teamIndex: 1)
        let switched = e.state.sides[0].activeIndex == 1
        let logged = e.state.log.contains { $0.contains("뒤로 물러났다") }
        let pass = switched && logged
        print(pass ? "  ✓ \(label) — 공격 후 물러나고 다음 포켓몬이 나온다"
                   : "  ✗ \(label) — 교체되지 않았다 (activeIndex=\(e.state.sides[0].activeIndex))")
        return pass
    }

    /// 상태이상이 실제로 만들어내는 부가 효과들을 하나씩 확인한다.
    /// 로그만 나오고 수치가 안 바뀌는 종류의 버그를 잡기 위한 것이다.
    private static func statusSideEffects(_ chart: TypeChart, _ checked: inout Int) async -> Bool {
        var ok = true

        // 마비 — 스피드 절반 + 행동 불가 발생
        if var e = await Harness.engine(att: 143, def: 143,
                                        attMoves: ["splash"], defMoves: ["splash"],
                                        chart: chart, seed: 21) {
            // Harness 가 스피드를 1 로 고정하므로 그대로 재면 1 → 1 이라 아무것도 검증되지 않는다.
            // 의미 있는 값을 넣고 잰다.
            var b = e.state.sides[1].team[0]
            b.stats[.speed] = 200
            let normal = b.effective(.speed)
            b.status = .paralysis
            e.state.sides[1].team[0] = b
            let para = e.state.sides[1].team[0].effective(.speed)
            ok = show(normal == 200 && para == 100,
                      "마비 — 스피드 정확히 절반", "\(normal) → \(para)") && ok
            checked += 1
        }
        var paralyzedBlocked = false
        for seed in 1...40 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["splash"], defMoves: ["body-slam"],
                                               chart: chart, seed: UInt64(seed) * 17) else { break }
            e.state.sides[1].team[0].status = .paralysis
            e.state.sides[1].team[0].maxHP = 99999
            e.state.sides[1].team[0].currentHP = 99999
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if e.state.log.contains(where: { $0.contains("몸이 굳어") }) { paralyzedBlocked = true; break }
        }
        ok = show(paralyzedBlocked, "마비 — 확률로 행동 불가") && ok; checked += 1

        // 화상 — 물리 공격 절반 (특수 불변) 은 --edgetest 에서 확인, 여기선 지속 피해
        if var e = await Harness.engine(att: 143, def: 143,
                                        attMoves: ["splash"], defMoves: ["splash"],
                                        chart: chart, seed: 33) {
            e.state.sides[1].team[0].status = .burn
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            let after = e.state.sides[1].team[0].currentHP
            ok = show(after < before, "화상 — 턴 종료 지속 피해", "\(before) → \(after)") && ok
            checked += 1
        }

        // 얼음 — 행동 불가, 그리고 해제됨
        var frozenBlocked = false
        for seed in 1...20 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["splash"], defMoves: ["body-slam"],
                                               chart: chart, seed: UInt64(seed) * 29) else { break }
            e.state.sides[1].team[0].status = .freeze
            e.state.sides[1].team[0].maxHP = 99999
            e.state.sides[1].team[0].currentHP = 99999
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if e.state.log.contains(where: { $0.contains("얼어붙어") }) { frozenBlocked = true; break }
        }
        ok = show(frozenBlocked, "얼음 — 행동 불가") && ok; checked += 1

        // 잠듦 — 행동 불가
        var asleepBlocked = false
        for seed in 1...20 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["splash"], defMoves: ["body-slam"],
                                               chart: chart, seed: UInt64(seed) * 37) else { break }
            e.state.sides[1].team[0].status = .sleep
            e.state.sides[1].team[0].sleepTurns = 3
            e.state.sides[1].team[0].maxHP = 99999
            e.state.sides[1].team[0].currentHP = 99999
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if e.state.log.contains(where: { $0.contains("쿨쿨") }) { asleepBlocked = true; break }
        }
        ok = show(asleepBlocked, "잠듦 — 행동 불가") && ok; checked += 1

        // 혼란 — 자신을 공격하는 경우가 발생
        var confusedSelfHit = false
        for seed in 1...60 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["splash"], defMoves: ["body-slam"],
                                               chart: chart, seed: UInt64(seed) * 43) else { break }
            e.state.sides[1].team[0].confusionTurns = 5
            e.state.sides[1].team[0].maxHP = 99999
            e.state.sides[1].team[0].currentHP = 99999
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if e.state.log.contains(where: { $0.contains("자신을 공격") }) { confusedSelfHit = true; break }
        }
        ok = show(confusedSelfHit, "혼란 — 자신을 공격") && ok; checked += 1

        // 상태이상은 중복으로 걸리지 않는다
        if var e = await Harness.engine(att: 143, def: 143,
                                        attMoves: ["thunder-wave"], defMoves: ["splash"],
                                        chart: chart, seed: 55) {
            e.state.sides[1].team[0].status = .burn
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            ok = show(e.state.sides[1].team[0].status == .burn,
                      "이미 상태이상이면 다른 상태이상이 안 걸린다",
                      "\(e.state.sides[1].team[0].status.ko)") && ok
            checked += 1
        }

        // 근성 — 상태이상일 때 공격 상승 (특성과 상태이상의 상호작용)
        if let guts = await AbilityCatalog.shared.ability("guts") {
            func dealt(_ burned: Bool, _ ab: AbilityDef?) async -> Int? {
                guard let sp = try? await PokeAPI.shared.species(143),
                      let mv = try? await PokeAPI.shared.move("body-slam"),
                      let splash = try? await PokeAPI.shared.move("splash"),
                      let chartOK = try? await PokeAPI.shared.typeChart() else { return nil }
                let slot = RosterSlot(id: "g", speciesID: 143, nature: "serious",
                                      rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
                var a = Battler.make(slot: slot, species: sp, moves: [mv], level: 50, ability: ab)
                a.stats[.speed] = 999
                if burned { a.status = .burn }
                var d = Battler.make(slot: RosterSlot(id: "d", speciesID: 143, nature: "serious",
                                                      rarity: "common", isShiny: false,
                                                      origin: .dex, fullyEvolved: true),
                                     species: sp, moves: [splash], level: 50)
                d.stats[.speed] = 1; d.maxHP = 99999; d.currentHP = 99999
                var rules = BattleRules(maxTeamSize: 1, level: 50)
                rules.requireItems = false
                var st = BattleState(rules: rules,
                                     sides: [SideState(playerName: "A", team: [a], activeIndex: 0),
                                             SideState(playerName: "B", team: [d], activeIndex: 0)])
                st.phase = .awaitingMoves
                var e2 = BattleEngine(state: st, chart: chartOK, seed: 606)
                let before = e2.state.sides[1].team[0].currentHP
                e2.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                return before - e2.state.sides[1].team[0].currentHP
            }
            if let plain = await dealt(true, nil), let withGuts = await dealt(true, guts) {
                ok = show(withGuts > plain, "근성 — 화상 중에도 공격이 오른다",
                          "\(plain) → \(withGuts)") && ok
                checked += 1
            }
        }
        return ok
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }

    private static func battler(_ sp: SpeciesDef, moves: [MoveDef], id: String) -> Battler {
        let slot = RosterSlot(id: id, speciesID: sp.id, nature: "serious",
                              rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
        return Battler.make(slot: slot, species: sp, moves: moves, level: 50)
    }
}
