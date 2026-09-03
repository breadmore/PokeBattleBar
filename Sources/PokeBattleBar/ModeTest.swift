import Foundation

/// `PokeBattleBar --modetest`
/// 게임 모드 4종이 실제로 작동하는지 확인한다.
enum ModeTest {
    static func run() async -> Bool {
        print("=== 게임 모드 검증 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else { return false }
        await ItemCatalog.shared.loadAll()
        var ok = true

        // MARK: 토게피 손가락흔들기
        print("-- 토게피 손가락흔들기 1:1 --")
        ok = show(GameModes.Metronome.speciesID == 175, "종은 토게피(#175)") && ok

        guard var mv = try? await PokeAPI.shared.move("metronome") else {
            print("  ✗ 손가락흔들기 로드 실패"); return false
        }
        let basePP = mv.pp
        let maxed = GameModes.maxPP(base: basePP)
        ok = show(maxed > basePP, "PP 를 최대치로 올린다", "\(basePP) → \(maxed)") && ok
        ok = show(GameModes.maxPP(base: 10) == 16, "PP Up 3회 공식 (10 → 16)",
                  "\(GameModes.maxPP(base: 10))") && ok
        ok = show(GameModes.maxPP(base: 35) == 56, "PP Up 3회 공식 (35 → 56)",
                  "\(GameModes.maxPP(base: 35))") && ok

        // 풀 준비
        print("\n  손가락흔들기 기술 풀을 받는 중… (\(GameModes.uniquePool.count)개)")
        var pool: [MoveDef] = []
        for n in GameModes.uniquePool {
            if let m = try? await PokeAPI.shared.move(n) { pool.append(m) }
        }
        ok = show(pool.count >= GameModes.uniquePool.count - 5,
                  "풀 로드", "\(pool.count)/\(GameModes.uniquePool.count)개") && ok
        ok = show(!pool.contains { $0.name == "metronome" }, "풀에 손가락흔들기 자신은 없다") && ok
        ok = show(!pool.contains { $0.name.contains("--") || $0.name.hasPrefix("max-") },
                  "풀에 Z기술·맥스기술은 없다") && ok
        let damaging = pool.filter(\.isDamaging).count
        ok = show(damaging >= pool.count / 3, "풀에 공격기가 충분하다",
                  "\(damaging)/\(pool.count)") && ok

        // 실제 배틀 — 손가락흔들기가 매번 다른 기술을 부르는가
        mv.pp = maxed
        guard let togepi = try? await PokeAPI.shared.species(175),
              let orb = await ItemCatalog.shared.item("life-orb") else {
            print("  ✗ 토게피/생명의구슬 로드 실패"); return false
        }
        // HP 를 크게 잡으면 생명의구슬 반동(최대HP의 10%) 도 같이 커져 금방 자멸한다.
        // 실제 HP 로 짧은 배틀을 여러 번 돌려 표본을 모은다.
        var called = Set<String>()
        var sawMetronome = false, sawOrb = false
        for seed in 1...25 {
            var e = engine(togepi, mv, orb, chart, pool,
                           seed: UInt64(seed) * 5171, maxHP: nil)
            for _ in 0..<12 {
                guard case .awaitingMoves = e.state.phase else { break }
                let before = e.state.log.count
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                for line in e.state.log[before...] where line.contains("의 ") && line.hasSuffix("!") {
                    called.insert(line)
                }
            }
            if e.state.log.contains(where: { $0.contains("손가락흔들기") }) { sawMetronome = true }
            if e.state.log.contains(where: { $0.contains("생명의구슬") }) { sawOrb = true }
        }
        // 무슨 기술이 나왔고 그게 어떤 기술인지(타입·위력)까지 로그에 남아야 한다.
        // 손가락흔들기 대전에서는 모르는 기술이 나오므로 이름만으로는 알 수 없다.
        var sawDetail = false
        do {
            var e = engine(togepi, mv, orb, chart, pool, seed: 4242, maxHP: nil)
            for _ in 0..<12 {
                guard case .awaitingMoves = e.state.phase else { break }
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            }
            sawDetail = e.state.log.contains { $0.contains("위력") && $0.hasPrefix("(") }
        }
        ok = show(sawDetail, "불려나온 기술의 타입·위력도 알려준다") && ok

        ok = show(called.count >= 20, "손가락흔들기가 여러 기술을 부른다",
                  "서로 다른 로그 \(called.count)종") && ok
        ok = show(sawMetronome, "로그에 손가락흔들기가 남는다") && ok
        ok = show(sawOrb, "생명의구슬 반동이 작동한다") && ok

        // PP 가 최대치에서 시작해 줄어드는가
        var e2 = engine(togepi, mv, orb, chart, pool, seed: 77, maxHP: nil)
        let ppStart = e2.state.sides[0].team[0].moves[0].ppLeft
        e2.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let ppAfter = e2.state.sides[0].team[0].moves[0].ppLeft
        ok = show(ppStart == maxed && ppAfter == maxed - 1,
                  "PP 가 최대치에서 시작해 1 줄어든다", "\(ppStart) → \(ppAfter)") && ok

        // MARK: 자유의지
        print("\n-- 자유의지 (자동 행동) --")
        guard var e3 = await Harness.engine(att: 143, def: 143,
                                            attMoves: ["body-slam", "hyper-voice",
                                                       "swords-dance", "recover"],
                                            defMoves: ["splash"],
                                            chart: chart, seed: 9090) else {
            print("  ✗ 준비 실패"); return false
        }
        e3.state.rules.autoMove = true
        var picked = Set<Int>()
        for _ in 0..<40 {
            guard case .awaitingMoves = e3.state.phase else { break }
            let a = e3.autoAction(for: .host)
            if let i = a.moveIndex { picked.insert(i) }
            e3.resolveTurn(hostAction: a, guestAction: e3.autoAction(for: .guest))
        }
        ok = show(picked.count >= 3, "4개 기술 중 무작위로 고른다",
                  "\(picked.sorted()) 사용") && ok

        // MARK: 변신 자동 선언
        print("\n-- 변신 자동 선언 --")
        ok = await autoSpecialFires(chart) && ok

        // MARK: 랜덤 기술 (저장본을 덮지 않는지)
        print("\n-- 랜덤 기술 --")
        guard let sp = try? await PokeAPI.shared.species(143) else { return false }
        let slot = RosterSlot(id: "randomtest", speciesID: 143, nature: "serious",
                              rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
        let saved = await MovesetStore.shared.moveset(for: slot, species: sp).map(\.name)
        var draws = Set<String>()
        for _ in 0..<8 {
            let d = await MovesetStore.shared.drawWithoutSaving(species: sp)
            draws.insert(d.map(\.name).sorted().joined(separator: ","))
        }
        let savedAfter = await MovesetStore.shared.moveset(for: slot, species: sp).map(\.name)
        ok = show(draws.count >= 2, "매번 다른 기술 조합이 나온다", "\(draws.count)종") && ok
        ok = show(saved == savedAfter, "저장된 기술을 덮어쓰지 않는다") && ok

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }

    /// 토게피 1:1 엔진
    private static func engine(_ sp: SpeciesDef, _ mv: MoveDef, _ orb: ItemDef,
                               _ chart: TypeChart, _ pool: [MoveDef],
                               seed: UInt64, maxHP: Int?) -> BattleEngine {
        func mk(_ tag: String) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id,
                                  nature: GameModes.Metronome.nature, rarity: "common",
                                  isShiny: false, origin: .dex, fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: [mv], level: 50,
                                 heldItem: orb, ability: nil)
            b.moves[0].ppLeft = mv.pp
            if let maxHP { b.maxHP = maxHP; b.currentHP = maxHP }
            return b
        }
        var rules = BattleRules(maxTeamSize: 1, level: 50)
        rules.metronomeMode = true
        rules.requireItems = false
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: [mk("a")], activeIndex: 0),
                                     SideState(playerName: "B", team: [mk("b")], activeIndex: 0)])
        st.phase = .awaitingMoves
        st.turn = 1
        var e = BattleEngine(state: st, chart: chart, seed: seed)
        e.metronomePool = pool
        return e
    }

    /// 도구를 끼우면 변신이 자동으로 발동하는가
    private static func autoSpecialFires(_ chart: TypeChart) async -> Bool {
        guard let sp = try? await PokeAPI.shared.species(65),          // 후딘 (메가 O)
              let stone = await ItemCatalog.shared.item("alakazite"),
              let mv = try? await PokeAPI.shared.move("psychic"),
              let splash = try? await PokeAPI.shared.move("splash"),
              let dSp = try? await PokeAPI.shared.species(143) else {
            return show(false, "변신 자동 선언", "준비 실패")
        }
        for seed in 1...20 {
            func mk(_ s: SpeciesDef, _ m: [MoveDef], _ it: ItemDef?, _ tag: String) -> Battler {
                let slot = RosterSlot(id: tag, speciesID: s.id, nature: "serious",
                                      rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
                var b = Battler.make(slot: slot, species: s, moves: m, level: 50, heldItem: it)
                for i in b.moves.indices { b.moves[i].ppLeft = 99 }
                b.maxHP = 99999; b.currentHP = 99999
                return b
            }
            var rules = BattleRules(maxTeamSize: 1, level: 50)
            rules.autoMove = true
            rules.autoSpecial = true
            rules.requireItems = true
            var st = BattleState(rules: rules,
                                 sides: [SideState(playerName: "A", team: [mk(sp, [mv], stone, "a")], activeIndex: 0),
                                         SideState(playerName: "B", team: [mk(dSp, [splash], nil, "b")], activeIndex: 0)])
            st.phase = .awaitingMoves
            st.turn = 1
            var e = BattleEngine(state: st, chart: chart, seed: UInt64(seed) * 313)
            e.megaCache["alakazam-mega"] = try? await PokeAPI.shared.form(named: "alakazam-mega")

            for _ in 0..<15 {
                guard case .awaitingMoves = e.state.phase else { break }
                e.resolveTurn(hostAction: e.autoAction(for: .host),
                              guestAction: e.autoAction(for: .guest))
                if e.state.sides[0].team[0].isMega {
                    return show(true, "메가스톤을 끼우면 자동으로 메가진화한다",
                                "시드 \(seed)")
                }
            }
        }
        return show(false, "변신 자동 선언", "20시드 15턴 동안 발동 안 함")
    }
}
