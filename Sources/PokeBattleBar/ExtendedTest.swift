import Foundation

/// `PokeBattleBar --extendedtest`
/// 날씨 · 접촉 특성 · G-Max 전용기가 실제로 작동하는지 확인한다.
/// 이 셋은 PokeAPI 에 데이터가 없어 직접 표로 넣은 것들이라, 특히 검증이 필요하다.
enum ExtendedTest {

    static func run() async -> Bool {
        print("=== 날씨 · 접촉 · G-Max 검증 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else { return false }
        var ok = true

        // MARK: 날씨
        print("-- 날씨 --")
        ok = show(Weather.from(moveName: "sunny-day") == .sun, "쾌청 기술 인식") && ok
        ok = show(Weather.from(moveName: "rain-dance") == .rain, "비바라기 기술 인식") && ok
        ok = show(Weather.from(moveName: "sandstorm") == .sandstorm, "모래바람 기술 인식") && ok
        ok = show(Weather.sun.damageMultiplier(for: .fire) == 1.5, "쾌청 → 불꽃 1.5배") && ok
        ok = show(Weather.sun.damageMultiplier(for: .water) == 0.5, "쾌청 → 물 0.5배") && ok
        ok = show(Weather.rain.damageMultiplier(for: .water) == 1.5, "비 → 물 1.5배") && ok

        ok = await weatherLog("sunny-day", needle: "쾌청 상태가 되었다", chart,
                              "쾌청 기술로 날씨 변경") && ok
        ok = await weatherLog("sandstorm", needle: "모래바람에 시달리고", chart,
                              "모래바람 지속 피해") && ok
        ok = await weatherDamage("sunny-day", move: "flamethrower", chart,
                                 "쾌청에서 불꽃 기술 강화", expectMore: true) && ok
        ok = await weatherDamage("rain-dance", move: "flamethrower", chart,
                                 "비에서 불꽃 기술 약화", expectMore: false) && ok

        // 날씨 특성
        ok = await abilityLog("drought", chart, needle: "쾌청 상태가 되었다",
                              "가뭄 — 등장 시 쾌청", onEntry: true) && ok
        ok = await abilityLog("drizzle", chart, needle: "비 상태가 되었다",
                              "잔비 — 등장 시 비", onEntry: true) && ok
        ok = await abilityLog("sand-stream", chart, needle: "모래바람 상태가 되었다",
                              "모래날림 — 등장 시 모래바람", onEntry: true) && ok

        // MARK: 접촉
        print("\n-- 접촉 기술 판정 --")
        ok = show(MoveFlags.isContact("tackle"), "몸통박치기는 접촉") && ok
        ok = show(!MoveFlags.isContact("flamethrower"), "화염방사는 비접촉") && ok
        ok = show(MoveFlags.isPunch("fire-punch"), "불꽃펀치는 펀치 기술") && ok
        ok = show(MoveFlags.isBite("crunch"), "깨물어부수기는 물기 기술") && ok
        ok = show(MoveFlags.isSound("hyper-voice"), "하이퍼보이스는 소리 기술") && ok
        ok = show(MoveFlags.isPowder("sleep-powder"), "수면가루는 가루 기술") && ok

        print("\n-- 접촉 특성 --")
        ok = await contactAbility("static", move: "tackle", chart,
                                  needle: "마비", "정전기 — 접촉 시 마비") && ok
        ok = await contactAbility("flame-body", move: "tackle", chart,
                                  needle: "화상", "불꽃몸 — 접촉 시 화상") && ok
        // PokeAPI 의 한글명은 "까칠한피부" — 로그도 그 이름으로 나온다
        ok = await contactAbility("rough-skin", move: "tackle", chart,
                                  needle: "때문에 피해를 입었다", "까칠한피부 — 접촉 시 반사 피해") && ok
        ok = await contactAbility("iron-barbs", move: "tackle", chart,
                                  needle: "때문에 피해를 입었다", "철가시 — 접촉 시 반사 피해") && ok
        ok = await contactAbility("static", move: "flamethrower", chart,
                                  needle: "마비", "비접촉 기술에는 정전기 발동 안 함",
                                  expectAbsent: true) && ok

        // 소리 / 가루 면역
        ok = await immunityLog("soundproof", move: "hyper-voice", chart,
                               needle: "방음으로 소리 기술을 막았다", "방음 — 소리 기술 무효") && ok
        ok = await grassPowder(chart) && ok

        // 기술 종류 강화
        ok = await abilityDamage("iron-fist", move: "fire-punch", chart,
                                 onAttacker: true, "철주먹 — 펀치 기술 강화") && ok
        ok = await abilityDamage("strong-jaw", move: "crunch", chart,
                                 onAttacker: true, "옹골찬턱 — 물기 기술 강화") && ok

        // MARK: G-Max
        print("\n-- G-Max 전용기 --")
        ok = show(GMaxMove.speciesCount >= 32, "거다이맥스 종 등록",
                  "\(GMaxMove.speciesCount)종") && ok
        ok = show(GMaxMove.forSpecies(6) == .wildfire, "리자몽 → 다이맥스파이어") && ok
        ok = show(GMaxMove.forSpecies(143) == .replenish, "잠만보 → 다이맥스이팅") && ok
        ok = show(GMaxMove.forSpecies(94) == .terror, "팬텀 → 다이맥스고스트") && ok
        ok = show(GMaxMove.forSpecies(317) == nil, "꿀꺽몬은 전용기 없음") && ok
        ok = show(GMaxMove.wildfire.type == .fire, "다이맥스파이어는 불꽃 타입") && ok

        let implemented = allGMax().filter { $0.effect.isImplemented }.count
        print("  구현된 추가효과: \(implemented)/\(allGMax().count)종")

        ok = await gmaxSignature(species: 6, move: "flamethrower", chart,
                                 needle: "다이맥스파이어", "리자몽 거다이맥스 → 전용기로 변환") && ok
        ok = await gmaxSignature(species: 6, move: "flamethrower", chart,
                                 needle: "여파가 상대를 감쌌다", "다이맥스파이어 지속 피해 부여") && ok
        ok = await gmaxSignature(species: 25, move: "thunderbolt", chart,
                                 needle: "마비", "다이맥스썬더 → 마비") && ok
        ok = await gmaxSignature(species: 99, move: "surf", chart,
                                 needle: "스피드", "다이맥스버블 → 상대 스피드 하락") && ok
        ok = await gmaxSignature(species: 68, move: "close-combat", chart,
                                 needle: "급소율이 올라갔다", "다이맥스태클 → 급소율 상승") && ok
        // 타입이 다르면 전용기가 아니라 일반 맥스 기술
        ok = await gmaxSignature(species: 6, move: "earthquake", chart,
                                 needle: "다이맥스파이어", "타입이 다르면 전용기 아님",
                                 expectAbsent: true) && ok

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func allGMax() -> [GMaxMove] {
        (0...1000).compactMap { GMaxMove.forSpecies($0) }
    }

    private static func show(_ c: Bool, _ l: String, _ got: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(got.isEmpty ? "" : "  (\(got))")"
                : "  ✗ \(l)\(got.isEmpty ? "" : "  — 실제: \(got)")")
        return c
    }

    // MARK: 시나리오

    private static func build(attacker: Int, defender: Int,
                              attMoves: [String], defMoves: [String],
                              attAbility: String?, defAbility: String?,
                              chart: TypeChart, seed: UInt64,
                              gigantamax: Bool = false) async -> BattleEngine? {
        guard let aSp = try? await PokeAPI.shared.species(attacker),
              let dSp = try? await PokeAPI.shared.species(defender) else { return nil }
        var aM: [MoveDef] = [], dM: [MoveDef] = []
        for n in attMoves { if let m = try? await PokeAPI.shared.move(n) { aM.append(m) } }
        for n in defMoves { if let m = try? await PokeAPI.shared.move(n) { dM.append(m) } }
        guard !aM.isEmpty, !dM.isEmpty else { return nil }

        let aa = attAbility == nil ? nil : await AbilityCatalog.shared.ability(attAbility!)
        let da = defAbility == nil ? nil : await AbilityCatalog.shared.ability(defAbility!)

        func mk(_ sp: SpeciesDef, _ mv: [MoveDef], _ ab: AbilityDef?, _ tag: String) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: mv, level: 50, ability: ab)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            return b
        }
        var a = mk(aSp, aM, aa, "att"), d = mk(dSp, dM, da, "def")
        a.stats[.speed] = 999; d.stats[.speed] = 1
        d.stats[.defense] = 500; d.stats[.spDefense] = 500   // 배틀이 일찍 끝나지 않게

        var rules = BattleRules(maxTeamSize: 1, level: 50)
        rules.requireItems = false
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: [a], activeIndex: 0),
                                     SideState(playerName: "B", team: [d], activeIndex: 0)])
        st.phase = .awaitingMoves
        st.turn = 1
        var e = BattleEngine(state: st, chart: chart, seed: seed)
        if gigantamax, let g = aSp.gmaxForm {
            e.gmaxCache[g] = try? await PokeAPI.shared.form(named: g)
        }
        for (_, n) in FormTables.maxMove {
            if let m = try? await PokeAPI.shared.move(n) { e.maxMoveCache[n] = m }
        }
        if let g = try? await PokeAPI.shared.move(FormTables.maxGuard) {
            e.maxMoveCache[FormTables.maxGuard] = g
        }
        return e
    }

    private static func seek(_ label: String, needle: String, expectAbsent: Bool = false,
                             seeds: Int = 20,
                             _ body: @escaping (UInt64) async -> [String]?) async -> Bool {
        var last: [String] = []
        for i in 1...seeds {
            guard let log = await body(UInt64(i) * 7717) else {
                print("  ✗ \(label) — 준비 실패"); return false
            }
            last = log
            if log.contains(where: { $0.contains(needle) }) {
                if expectAbsent {
                    print("  ✗ \(label) — \"\(needle)\" 가 나왔다")
                    for l in log.prefix(6) { print("      \(l)") }
                    return false
                }
                print("  ✓ \(label)")
                return true
            }
        }
        if expectAbsent { print("  ✓ \(label)"); return true }
        print("  ✗ \(label) — 시드 \(seeds)회 모두 \"\(needle)\" 없음")
        for l in last.prefix(6) { print("      \(l)") }
        return false
    }

    private static func weatherLog(_ move: String, needle: String, _ chart: TypeChart,
                                   _ label: String) async -> Bool {
        await seek(label, needle: needle, seeds: 3) { seed in
            guard var e = await build(attacker: 143, defender: 143,
                                      attMoves: [move], defMoves: ["splash"],
                                      attAbility: nil, defAbility: nil,
                                      chart: chart, seed: seed) else { return nil }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if case .awaitingMoves = e.state.phase {
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            }
            return e.state.log
        }
    }

    private static func weatherDamage(_ setup: String, move: String, _ chart: TypeChart,
                                      _ label: String, expectMore: Bool) async -> Bool {
        func run(_ withWeather: Bool) async -> Int? {
            guard var e = await build(attacker: 143, defender: 143,
                                      attMoves: [setup, move], defMoves: ["splash"],
                                      attAbility: nil, defAbility: nil,
                                      chart: chart, seed: 24680) else { return nil }
            if withWeather {
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            }
            guard case .awaitingMoves = e.state.phase else { return nil }
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 1), guestAction: .useMove(index: 0))
            return before - e.state.sides[1].team[0].currentHP
        }
        guard let w = await run(true), let n = await run(false) else {
            print("  ✗ \(label) — 준비 실패"); return false
        }
        let pass = expectMore ? w > n : w < n
        print(pass ? "  ✓ \(label) (\(n) → \(w))" : "  ✗ \(label) — \(n) → \(w)")
        return pass
    }

    private static func abilityLog(_ ability: String, _ chart: TypeChart, needle: String,
                                   _ label: String, onEntry: Bool) async -> Bool {
        await seek(label, needle: needle, seeds: 3) { seed in
            guard var e = await build(attacker: 143, defender: 143,
                                      attMoves: ["splash"], defMoves: ["splash"],
                                      attAbility: ability, defAbility: nil,
                                      chart: chart, seed: seed) else { return nil }
            if onEntry { e.state.phase = .chooseLead; e.beginBattle() }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return e.state.log
        }
    }

    private static func contactAbility(_ ability: String, move: String, _ chart: TypeChart,
                                       needle: String, _ label: String,
                                       expectAbsent: Bool = false) async -> Bool {
        await seek(label, needle: needle, expectAbsent: expectAbsent, seeds: 30) { seed in
            guard var e = await build(attacker: 143, defender: 143,
                                      attMoves: [move], defMoves: ["splash"],
                                      attAbility: nil, defAbility: ability,
                                      chart: chart, seed: seed) else { return nil }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return e.state.log
        }
    }

    private static func immunityLog(_ ability: String, move: String, _ chart: TypeChart,
                                    needle: String, _ label: String) async -> Bool {
        await seek(label, needle: needle, seeds: 3) { seed in
            guard var e = await build(attacker: 143, defender: 143,
                                      attMoves: [move], defMoves: ["splash"],
                                      attAbility: nil, defAbility: ability,
                                      chart: chart, seed: seed) else { return nil }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return e.state.log
        }
    }

    /// 가루 기술은 풀타입에게 통하지 않는다 (이상해꽃 = 풀/독)
    private static func grassPowder(_ chart: TypeChart) async -> Bool {
        await seek("가루 기술은 풀타입에 무효", needle: "가루 기술이 통하지 않는다", seeds: 3) { seed in
            guard var e = await build(attacker: 143, defender: 3,
                                      attMoves: ["sleep-powder"], defMoves: ["splash"],
                                      attAbility: nil, defAbility: nil,
                                      chart: chart, seed: seed) else { return nil }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return e.state.log
        }
    }

    private static func abilityDamage(_ ability: String, move: String, _ chart: TypeChart,
                                      onAttacker: Bool, _ label: String) async -> Bool {
        func run(_ ab: String?) async -> Int? {
            guard var e = await build(attacker: 143, defender: 143,
                                      attMoves: [move], defMoves: ["splash"],
                                      attAbility: onAttacker ? ab : nil,
                                      defAbility: onAttacker ? nil : ab,
                                      chart: chart, seed: 13579) else { return nil }
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return before - e.state.sides[1].team[0].currentHP
        }
        guard let w = await run(ability), let n = await run(nil) else {
            print("  ✗ \(label) — 준비 실패"); return false
        }
        let pass = w > n
        print(pass ? "  ✓ \(label) (\(n) → \(w))" : "  ✗ \(label) — \(n) → \(w)")
        return pass
    }

    private static func gmaxSignature(species: Int, move: String, _ chart: TypeChart,
                                      needle: String, _ label: String,
                                      expectAbsent: Bool = false) async -> Bool {
        await seek(label, needle: needle, expectAbsent: expectAbsent, seeds: 6) { seed in
            guard var e = await build(attacker: species, defender: 143,
                                      attMoves: [move], defMoves: ["splash"],
                                      attAbility: nil, defAbility: nil,
                                      chart: chart, seed: seed, gigantamax: true) else { return nil }
            e.resolveTurn(hostAction: .useMove(index: 0, special: .gmax),
                          guestAction: .useMove(index: 0))
            return e.state.log
        }
    }
}
