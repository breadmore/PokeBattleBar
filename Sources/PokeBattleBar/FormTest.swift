import Foundation

/// `PokeBattleBar --formtest`
/// 메가진화 / 거다이맥스 / Z기술의 **자격 제한**과 **배틀당 1회 제한**을 검증한다.
/// 핵심 규칙: 6마리를 데려가도 메가 1회, 거다이맥스 1회, Z기술 1회씩만 쓸 수 있다.
enum FormTest {

    static func run(verbose: Bool) async -> Bool {
        print("=== 특수 변신 규칙 검증 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else {
            print("✗ 상성표 실패"); return false
        }
        // 도구 게이팅 검증에 필요하다
        await ItemCatalog.shared.loadAll()
        var ok = true

        // 리자몽(메가X/Y + 거다이맥스), 팬텀(메가 + 거다이맥스), 잠만보(거다이맥스만),
        // 꿀꺽몬(아무것도 없음), 후딘(메가만), 쥬레곤(없음)
        let ids = [6, 94, 143, 317, 65, 87]
        print("-- 자격 확인 --")
        for id in ids {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            print("  \(sp.display.padding(toLength: 10, withPad: " ", startingAt: 0)) "
                  + "메가:\(sp.canMega ? sp.megaForms.joined(separator: ",") : "✗")  "
                  + "거다이맥스:\(sp.gmaxForm ?? "✗")")
        }

        ok = await check(6,   mega: true,  gmax: true,  "리자몽 = 메가O 거다이맥스O") && ok
        ok = await check(143, mega: false, gmax: true,  "잠만보 = 메가X 거다이맥스O") && ok
        ok = await check(65,  mega: true,  gmax: false, "후딘 = 메가O 거다이맥스X") && ok
        ok = await check(317, mega: false, gmax: false, "꿀꺽몬 = 둘 다 X") && ok
        ok = await check(87,  mega: false, gmax: false, "쥬레곤 = 둘 다 X") && ok

        // --- 실제 배틀에서 규칙이 지켜지는지 ---
        print("\n-- 배틀당 1회 제한 --")
        guard var e = await makeEngine(ids: [6, 94, 143], chart: chart) else {
            print("✗ 엔진 준비 실패"); return false
        }

        // 1턴: 리자몽 메가진화
        e.resolveTurn(hostAction: .useMove(index: 0, special: .mega(form: "charizard-mega-x")),
                      guestAction: .useMove(index: 0))
        let megaOK = e.state.sides[0].team[0].isMega && e.state.sides[0].usedMega
        ok = show(megaOK, "메가진화 발동 + 사용 기록", e.state.sides[0].team[0].formLabel ?? "-") && ok

        // 메가 후 타입이 바뀌었는지 (리자몽 불꽃/비행 → 메가X 불꽃/드래곤)
        let types = e.state.sides[0].team[0].types
        ok = show(types.contains(.dragon), "메가X 타입 변경 (불꽃/드래곤)",
                  types.map(\.ko).joined(separator: "/")) && ok

        // 2턴: 같은 플레이어가 또 메가진화를 시도 → 거부되어야 한다
        guard case .awaitingMoves = e.state.phase else {
            print("  (배틀이 이미 끝나 이후 검증을 건너뜁니다)"); return ok
        }
        let logBefore = e.state.log.count
        e.resolveTurn(hostAction: .useMove(index: 0, special: .mega(form: "charizard-mega-x")),
                      guestAction: .useMove(index: 0))
        let refused = e.state.log[logBefore...].contains { $0.contains("이미 사용") }
        ok = show(refused, "두 번째 메가진화 거부 (배틀당 1회)") && ok

        // 3턴: 다른 종류(Z기술)는 아직 쓸 수 있어야 한다
        if case .awaitingMoves = e.state.phase {
            let before = e.state.log.count
            e.resolveTurn(hostAction: .useMove(index: 0, special: .zMove),
                          guestAction: .useMove(index: 0))
            let zUsed = e.state.sides[0].usedZMove
            let zLogged = e.state.log[before...].contains { $0.contains("Z파워") }
            ok = show(zUsed && zLogged, "메가를 썼어도 Z기술은 별도로 1회 가능") && ok
        }

        // --- 자격 없는 포켓몬은 선언해도 무시 ---
        print("\n-- 자격 없는 포켓몬 --")
        if var e2 = await makeEngine(ids: [317, 87], chart: chart) {   // 꿀꺽몬 (폼 없음)
            e2.resolveTurn(hostAction: .useMove(index: 0, special: .gmax),
                           guestAction: .useMove(index: 0))
            let noGiga = !e2.state.sides[0].team[0].isDynamaxed && !e2.state.sides[0].usedDynamax
            ok = show(noGiga, "꿀꺽몬은 거다이맥스 선언이 무시된다 (횟수도 소모 안 함)") && ok
        }

        // --- 거다이맥스: HP 증가 + 3턴 후 해제 ---
        print("\n-- 거다이맥스 지속 --")
        if var e3 = await makeEngine(ids: [143, 6], chart: chart) {    // 잠만보
            let hpBefore = e3.state.sides[0].team[0].maxHP
            e3.resolveTurn(hostAction: .useMove(index: 0, special: .gmax),
                           guestAction: .useMove(index: 0))
            let after = e3.state.sides[0].team[0]
            ok = show(after.maxHP > hpBefore, "거다이맥스로 최대 HP 증가",
                      "\(hpBefore) → \(after.maxHP)") && ok
            ok = show(after.isDynamaxed, "거다이맥스 상태 진입", "남은 \(after.dynamaxTurnsLeft)턴") && ok

            // 턴을 넘겨 해제되는지
            var turns = 0
            while turns < 6, case .awaitingMoves = e3.state.phase,
                  e3.state.sides[0].team[e3.state.sides[0].activeIndex].isDynamaxed {
                e3.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                turns += 1
            }
            let cur = e3.state.sides[0].team[e3.state.sides[0].activeIndex]
            let reverted = !cur.isDynamaxed
            ok = show(reverted, "거다이맥스 자동 해제", "\(turns)턴 경과, HP상한 \(cur.maxHP)") && ok
            if reverted {
                ok = show(cur.maxHP == cur.baseMaxHP, "해제 시 HP 상한 원복",
                          "\(cur.maxHP) vs 원래 \(cur.baseMaxHP)") && ok
            }
        }

        // --- 다이맥스와 거다이맥스는 슬롯을 공유하는가 ---
        print("\n-- 다이맥스 / 거다이맥스 슬롯 공유 --")
        if var e4 = await makeEngine(ids: [143, 6], chart: chart) {   // 잠만보 (거다이맥스 가능)
            e4.resolveTurn(hostAction: .useMove(index: 0, special: .dynamax),
                           guestAction: .useMove(index: 0))
            let dyn = e4.state.sides[0].team[0].isDynamaxed && !e4.state.sides[0].team[0].isGigantamaxed
            ok = show(dyn, "다이맥스 발동 (거다이맥스 아님)",
                      e4.state.sides[0].team[0].formLabel ?? "-") && ok
            ok = show(e4.state.sides[0].usedDynamax, "다이맥스 슬롯 소모") && ok

            // 같은 배틀에서 거다이맥스 시도 → 거부되어야 한다
            if case .awaitingMoves = e4.state.phase {
                let before = e4.state.log.count
                e4.resolveTurn(hostAction: .useMove(index: 0, special: .gmax),
                               guestAction: .useMove(index: 0))
                let refused = e4.state.log[before...].contains { $0.contains("이미 사용") }
                ok = show(refused, "다이맥스를 썼으면 거다이맥스 불가 (같은 슬롯)") && ok
            }
        }
        if var e5 = await makeEngine(ids: [317, 87], chart: chart) {   // 꿀꺽몬 (폼 없음)
            e5.resolveTurn(hostAction: .useMove(index: 0, special: .dynamax),
                           guestAction: .useMove(index: 0))
            ok = show(e5.state.sides[0].team[0].isDynamaxed,
                      "폼이 없는 포켓몬도 다이맥스는 가능 (종족 제한 없음)") && ok
        }

        // --- 서로 다른 두 마리가 각각 다른 도구로 다이맥스할 수 있는가 ---
        // 잠만보(다이버섯) + 뮤(다이맥스 밴드) 처럼 도구를 나눠 끼면
        // 한 배틀에 두 마리가 변신할 수 있는지 — 슬롯 공유가 진짜인지 확인한다.
        print("\n-- 서로 다른 두 마리 (도구를 나눠 낀 경우) --")
        ok = await twoPokemonShareSlot(chart) && ok

        // --- 위력 변환표 ---
        print("\n-- 위력 변환표 --")
        ok = show(FormTables.zPower(basePower: 40) == 100, "Z: 위력40 → 100") && ok
        ok = show(FormTables.zPower(basePower: 90) == 175, "Z: 위력90 → 175") && ok
        ok = show(FormTables.zPower(basePower: 250) == 200, "Z: 위력250 → 200 (상한)") && ok
        ok = show(FormTables.maxPower(basePower: 40, type: .fire) == 90, "맥스: 불꽃 위력40 → 90") && ok
        ok = show(FormTables.maxPower(basePower: 40, type: .fighting) == 70,
                  "맥스: 격투 위력40 → 70 (낮은 표)") && ok
        ok = show(FormTables.zMoveBase.count == 18, "Z기술 18타입 매핑") && ok
        ok = show(FormTables.maxMove.count == 18, "맥스기술 18타입 매핑") && ok

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    /// 팀에 두 마리를 두고, 첫 마리가 다이맥스한 뒤 쓰러지면
    /// 두 번째 마리가 거다이맥스를 시도한다. 슬롯을 공유하면 거부되어야 한다.
    private static func twoPokemonShareSlot(_ chart: TypeChart) async -> Bool {
        guard let mew = try? await PokeAPI.shared.species(151),      // 뮤 — 거다이맥스 폼 없음
              let snorlax = try? await PokeAPI.shared.species(143),  // 잠만보 — 거다이맥스 O
              let tackle = try? await PokeAPI.shared.move("tackle"),
              let splash = try? await PokeAPI.shared.move("splash"),
              let band = await ItemCatalog.shared.item("dynamax-band"),
              let mush = await ItemCatalog.shared.item("max-mushrooms") else {
            return show(false, "두 마리 슬롯 공유", "준비 실패")
        }

        func mk(_ sp: SpeciesDef, _ item: ItemDef, _ tag: String) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: [tackle], level: 50, heldItem: item)
            b.moves[0].ppLeft = 99
            return b
        }
        // 1번: 뮤(다이맥스 밴드), 2번: 잠만보(다이버섯)
        var a1 = mk(mew, band, "a1")
        let a2 = mk(snorlax, mush, "a2")
        a1.stats[.speed] = 999

        func foe(_ tag: String) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: 143, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            var b = Battler.make(slot: slot, species: snorlax, moves: [splash], level: 50)
            b.moves[0].ppLeft = 99
            b.stats[.speed] = 1
            return b
        }

        var rules = BattleRules(maxTeamSize: 6, level: 50)
        rules.requireItems = true     // 도구 게이팅을 켠 실제 조건
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: [a1, a2], activeIndex: 0),
                                     SideState(playerName: "B", team: [foe("b1")], activeIndex: 0)])
        st.phase = .awaitingMoves
        st.turn = 1
        var e = BattleEngine(state: st, chart: chart, seed: 5555)
        if let g = snorlax.gmaxForm { e.gmaxCache[g] = try? await PokeAPI.shared.form(named: g) }
        for (_, n) in FormTables.maxMove {
            if let m = try? await PokeAPI.shared.move(n) { e.maxMoveCache[n] = m }
        }
        if let g = try? await PokeAPI.shared.move(FormTables.maxGuard) {
            e.maxMoveCache[FormTables.maxGuard] = g
        }

        // 1턴: 뮤가 다이맥스 밴드로 다이맥스
        e.resolveTurn(hostAction: .useMove(index: 0, special: .dynamax),
                      guestAction: .useMove(index: 0))
        var ok = show(e.state.sides[0].team[0].isDynamaxed && e.state.sides[0].usedDynamax,
                      "1번(뮤)이 다이맥스 밴드로 다이맥스") 

        // 뮤를 쓰러뜨리고 잠만보로 교체
        e.state.sides[0].team[0].currentHP = 0
        e.state.phase = .awaitingReplacement([0])
        e.applyReplacement(.host, teamIndex: 1)
        guard case .awaitingMoves = e.state.phase else {
            return show(false, "두 마리 슬롯 공유", "교체 후 행동 단계가 아님") && ok
        }

        // 2턴: 잠만보가 다이버섯으로 거다이맥스 시도 → 거부되어야 한다
        let before = e.state.log.count
        e.resolveTurn(hostAction: .useMove(index: 0, special: .gmax),
                      guestAction: .useMove(index: 0))
        let second = e.state.sides[0].team[1]
        let refused = e.state.log[before...].contains { $0.contains("이미 사용") }

        ok = show(!second.isDynamaxed,
                  "2번(잠만보)은 다이버섯이 있어도 거다이맥스 불가",
                  second.isDynamaxed ? "변신해버렸다" : "차단됨") && ok
        ok = show(refused, "거부 안내가 로그에 남는다") && ok
        if second.isDynamaxed {
            for l in e.state.log.suffix(6) { print("      \(l)") }
        }
        return ok
    }

    // MARK: 헬퍼

    private static func show(_ cond: Bool, _ label: String, _ detail: String? = nil) -> Bool {
        let d = detail.map { "  (\($0))" } ?? ""
        print(cond ? "  ✓ \(label)\(d)" : "  ✗ \(label)\(d)")
        return cond
    }

    private static func check(_ id: Int, mega: Bool, gmax: Bool, _ label: String) async -> Bool {
        guard let sp = try? await PokeAPI.shared.species(id) else {
            print("  ✗ \(label) — 로드 실패"); return false
        }
        return show(sp.canMega == mega && sp.canGigantamax == gmax, label)
    }

    private static func makeEngine(ids: [Int], chart: TypeChart) async -> BattleEngine? {
        var teamA: [Battler] = [], teamB: [Battler] = []
        var megaCache: [String: FormStats] = [:], gmaxCache: [String: FormStats] = [:]
        var zCache: [String: MoveDef] = [:], maxCache: [String: MoveDef] = [:]

        for (i, id) in ids.enumerated() {
            guard let sp = try? await PokeAPI.shared.species(id),
                  let tackle = try? await PokeAPI.shared.move("tackle") else { return nil }
            let slot = RosterSlot(id: "f-\(i)", speciesID: id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: [tackle], level: 50)
            b.moves[0].ppLeft = 99                       // PP 로 검증이 끊기지 않게
            b.currentHP = b.maxHP
            teamA.append(b)
            for f in sp.megaForms { megaCache[f] = try? await PokeAPI.shared.form(named: f) }
            if let g = sp.gmaxForm { gmaxCache[g] = try? await PokeAPI.shared.form(named: g) }
        }
        // 상대는 튼튼하게 (검증 중 배틀이 끝나지 않도록)
        guard let sp = try? await PokeAPI.shared.species(143),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }
        for i in 0..<3 {
            let slot = RosterSlot(id: "g-\(i)", speciesID: 143, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: [splash], level: 50)
            b.moves[0].ppLeft = 99
            b.stats[.defense] = 9999                      // 데미지를 거의 안 받게
            b.stats[.spDefense] = 9999
            teamB.append(b)
        }

        for (_, base) in FormTables.zMoveBase {
            for sfx in ["--physical", "--special"] {
                if let m = try? await PokeAPI.shared.move(base + sfx) { zCache[base + sfx] = m }
            }
        }
        for (_, n) in FormTables.maxMove {
            if let m = try? await PokeAPI.shared.move(n) { maxCache[n] = m }
        }
        if let g = try? await PokeAPI.shared.move(FormTables.maxGuard) { maxCache[FormTables.maxGuard] = g }

        // 이 테스트는 **횟수 규칙**(배틀당 1회)과 지속턴을 본다.
        // 도구 게이팅은 --loadouttest 가 따로 검증하므로 여기서는 도구 요구를 끈다.
        var rules = BattleRules(maxTeamSize: 6, level: 50)
        rules.requireItems = false
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: teamA, activeIndex: 0),
                                     SideState(playerName: "B", team: teamB, activeIndex: 0)])
        st.phase = .awaitingMoves
        st.turn = 1
        var e = BattleEngine(state: st, chart: chart, seed: 777)
        e.megaCache = megaCache
        e.gmaxCache = gmaxCache
        e.zMoveCache = zCache
        e.maxMoveCache = maxCache
        return e
    }
}
