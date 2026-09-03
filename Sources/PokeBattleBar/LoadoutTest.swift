import Foundation

/// `PokeBattleBar --loadouttest`
/// 지닌 도구와 특성이 배틀 계산에 **실제로** 반영되는지 확인한다.
/// 매핑만 맞고 엔진이 안 쓰면 의미가 없으므로, 전부 실제 턴을 굴려서 본다.
enum LoadoutTest {

    static func run(verbose: Bool) async -> Bool {
        print("=== 도구 · 특성 효과 검증 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else { return false }
        await ItemCatalog.shared.loadAll()
        var ok = true

        // MARK: 변신 도구 게이팅
        print("-- 변신에 도구가 필요한가 --")
        ok = await gate(.mega(form: "charizard-mega-x"), species: 6, item: nil,
                        expect: false, "메가스톤 없으면 메가진화 불가", chart) && ok
        ok = await gate(.mega(form: "charizard-mega-x"), species: 6, item: "charizardite-x",
                        expect: true, "리자몽나이트X 끼우면 메가진화 가능", chart) && ok
        ok = await gate(.mega(form: "charizard-mega-x"), species: 6, item: "charizardite-y",
                        expect: true, "리자몽나이트Y 끼우면 Y로 진화", chart) && ok
        ok = await gate(.dynamax, species: 143, item: nil,
                        expect: false, "다이맥스밴드 없으면 다이맥스 불가", chart) && ok
        ok = await gate(.dynamax, species: 143, item: "dynamax-band",
                        expect: true, "다이맥스밴드 끼우면 다이맥스 가능", chart) && ok
        ok = await gate(.gmax, species: 143, item: "max-mushrooms",
                        expect: true, "다이버섯 끼우면 거다이맥스 가능", chart) && ok
        // 두 도구의 역할이 겹치면 하나가 무의미해진다 — 양방향으로 막혔는지 확인한다
        ok = await gate(.gmax, species: 143, item: "dynamax-band",
                        expect: false, "다이맥스 밴드로는 거다이맥스 불가", chart) && ok
        ok = await gate(.dynamax, species: 143, item: "max-mushrooms",
                        expect: false, "다이버섯으로는 일반 다이맥스 불가", chart) && ok
        ok = await gate(.gmax, species: 143, item: nil,
                        expect: false, "도구 없으면 거다이맥스 불가", chart) && ok
        ok = await gate(.zMove, species: 143, item: nil,
                        expect: false, "Z크리스탈 없으면 Z기술 불가", chart) && ok

        // 노말 타입 기술을 가진 잠만보에 노말Z
        ok = await gate(.zMove, species: 143, item: "normalium-z", move: "body-slam",
                        expect: true, "노말Z + 노말 기술이면 Z기술 가능", chart) && ok
        ok = await gate(.zMove, species: 143, item: "firium-z", move: "body-slam",
                        expect: false, "불꽃Z 인데 불꽃 기술이 없으면 불가", chart) && ok

        // MARK: 도구 상시 효과
        print("\n-- 도구 상시 효과 --")
        ok = await damageCompare("choice-band", move: "body-slam", chart,
                                 "구애머리띠 — 물리 데미지 증가", expectMore: true) && ok
        ok = await damageCompare("life-orb", move: "body-slam", chart,
                                 "생명의구슬 — 데미지 증가", expectMore: true) && ok
        ok = await damageCompare("muscle-band", move: "body-slam", chart,
                                 "힘의머리띠 — 물리 데미지 증가", expectMore: true) && ok

        ok = await logContains("life-orb", move: "body-slam", chart,
                               needle: "생명의구슬의 반동", "생명의구슬 — 반동 발생") && ok
        ok = await logContains("leftovers", move: "splash", chart,
                               needle: "먹다남은음식", "먹다남은음식 — 턴마다 회복",
                               setup: { $0.currentHP = $0.maxHP / 2 }) && ok
        ok = await logContains("flame-orb", move: "splash", chart,
                               needle: "화상", "화염구슬 — 자신에게 화상") && ok
        ok = await logContains("focus-sash", move: "body-slam", chart,
                               needle: "기합의띠로 버텼다", "기합의띠 — 일격 방지",
                               onDefender: true, weakenDefender: true) && ok
        ok = await logContains("choice-band", move: "body-slam", chart,
                               needle: "구애머리띠 때문에", "구애머리띠 — 기술 고정",
                               twoTurnsDifferentMove: true) && ok
        ok = await logContains("assault-vest", move: "swords-dance", chart,
                               needle: "돌격조끼 때문에", "돌격조끼 — 변화기 금지") && ok

        // MARK: 특성
        print("\n-- 특성 --")
        ok = await abilityLog("sturdy", move: "body-slam", chart, onDefender: true,
                              needle: "옹골참으로 버텼다", "옹골참 — 일격 방지",
                              weakenDefender: true) && ok
        ok = await abilityLog("intimidate", move: "splash", chart, onDefender: false,
                              needle: "위협", "위협 — 등장 시 상대 공격 하락") && ok
        ok = await abilityLog("immunity", move: "toxic", chart, onDefender: true,
                              needle: "상태가 되지 않는다", "면역 — 독 무효") && ok
        // 버섯포자(spore) 는 명중 100% — 명중 실패로 판정에 도달하지 못하는 일이 없다
        ok = await abilityLog("insomnia", move: "spore", chart, onDefender: true,
                              needle: "상태가 되지 않는다", "불면 — 잠듦 무효") && ok
        ok = await abilityLog("clear-body", move: "growl", chart, onDefender: true,
                              needle: "능력치가 떨어지지 않는다", "클리어바디 — 하락 무효") && ok
        ok = await abilityLog("rock-head", move: "double-edge", chart, onDefender: false,
                              needle: "돌머리 덕분에", "돌머리 — 반동 없음") && ok

        // 부유: 땅 기술 무효
        ok = await abilityDamage("levitate", move: "earthquake", chart,
                                 expectZero: true, "부유 — 땅 기술 무효") && ok
        // 두꺼운지방: 불꽃 피해 감소
        ok = await abilityDamage("thick-fat", move: "flamethrower", chart,
                                 expectLess: true, "두꺼운지방 — 불꽃 피해 감소") && ok
        // 적응력: 자기타입일치 강화
        ok = await abilityDamage("adaptability", move: "body-slam", chart,
                                 onAttacker: true, expectMore: true, "적응력 — 일치 보너스 증가") && ok
        // 순수한힘: 공격 2배
        ok = await abilityDamage("huge-power", move: "body-slam", chart,
                                 onAttacker: true, expectMore: true, "순수한힘 — 공격 2배") && ok
        // 테크니션: 저위력 강화
        ok = await abilityDamage("technician", move: "tackle", chart,
                                 onAttacker: true, expectMore: true, "테크니션 — 저위력 강화") && ok
        // 매직가드: 독 데미지 무효
        ok = await abilityLog("magic-guard", move: "splash", chart, onDefender: true,
                              needle: "", "매직가드 — 독 지속피해 무효",
                              statusOnDefender: .poison, expectNoNeedle: "독 때문에") && ok

        // MARK: 장비 경고 (배틀당 1회 슬롯이 겹치는지)
        print("\n-- 장비 낭비 경고 --")
        ok = await warningTests() && ok

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func check(_ c: Bool, _ label: String, got: String = "") -> Bool {
        print(c ? "  ✓ \(label)" : "  ✗ \(label)" + (got.isEmpty ? "" : " — 실제: \(got)"))
        return c
    }

    /// 경고 계산은 @MainActor 의 AppModel 에 있으므로 그쪽에서 굴린다.
    @MainActor
    private static func warningTests() async -> Bool {
        var ok = true
        let m = AppModel()

        // 로스터를 손으로 구성한다 (잠만보=거다이맥스O, 뮤=전용Z, 후딘=메가O, 꿀꺽몬=없음)
        let ids = [143, 151, 65, 317]
        var roster: [RosterSlot] = []
        for (i, id) in ids.enumerated() {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            m.rosterSpecies[id] = sp
            let slot = RosterSlot(id: "w\(i)", speciesID: id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            roster.append(slot)
            m.itemsForSpecies[id] = await ItemCatalog.shared.available(forSpecies: sp)
            m.movesetsBySlot[slot.id] = await MovesetStore.shared.moveset(for: slot, species: sp)
        }
        m.roster = roster
        m.selectedSlotIDs = Set(roster.map(\.id))
        m.rules.maxTeamSize = 6

        func setItem(_ slotIdx: Int, _ name: String?) {
            m.loadouts[roster[slotIdx].id] = LoadoutStore.Loadout(item: name, ability: nil)
        }
        func titles() -> [String] { m.loadoutWarnings.map(\.title) }

        // 1) 도구 없음 → 경고 없음
        for i in roster.indices { setItem(i, nil) }
        ok = check(m.loadoutWarnings.isEmpty, "도구가 없으면 경고 없음",
                   got: "\(titles())") && ok

        // 2) 다이맥스 도구 하나만 → 경고 없음
        setItem(0, "max-mushrooms")            // 잠만보 = 거다이맥스
        ok = check(m.loadoutWarnings.isEmpty, "다이맥스 도구 1개는 경고 없음",
                   got: "\(titles())") && ok

        // 3) 밴드 + 버섯 → 슬롯이 겹치므로 경고 (님이 지적한 상황)
        setItem(1, "dynamax-band")             // 뮤 = 일반 다이맥스
        let dynWarn = m.loadoutWarnings.contains { $0.id == "dynamax" }
        ok = check(dynWarn, "다이맥스 밴드 + 다이버섯 → 경고", got: "\(titles())") && ok

        // 4) 메가스톤 2개 → 경고. 단 자기 스톤이 아니면 슬롯 경쟁이 아니다
        for i in roster.indices { setItem(i, nil) }
        setItem(2, "alakazite")                // 후딘 = 자기 스톤 (작동)
        ok = check(!m.loadoutWarnings.contains { $0.id == "mega" },
                   "메가스톤 1개는 경고 없음", got: "\(titles())") && ok

        // 5) 자격 없는 도구는 **애초에 목록에 나오지 않는다** (경고가 아니라 예방)
        //    꿀꺽몬(거다이맥스 불가)에게 다이버섯, 메가 불가 종에게 메가스톤이 안 보여야 한다
        // 이름 문자열로 판별하면 안 된다 — eviolite(진화의휘석) 처럼 "ite" 로 끝나는
        // 일반 배틀 도구가 섞인다. 반드시 kind 로 본다.
        let swalotItems = m.itemsForSpecies[317] ?? []
        let swalotMega = swalotItems.filter { if case .megaStone = $0.kind { return true }; return false }
        let swalotMush = swalotItems.filter { if case .maxMushroom = $0.kind { return true }; return false }
        ok = check(swalotMush.isEmpty,
                   "거다이맥스 불가 종에게는 다이버섯이 목록에 없다",
                   got: "\(swalotMush.map(\.display))") && ok
        ok = check(swalotMega.isEmpty,
                   "메가 불가 종에게는 메가스톤이 목록에 없다",
                   got: "\(swalotMega.map(\.display))") && ok

        // 후딘은 자기 스톤만 보여야 한다
        let alaMega = (m.itemsForSpecies[65] ?? []).compactMap { d -> String? in
            if case .megaStone(let f) = d.kind { return f }
            return nil
        }
        ok = check(alaMega == ["alakazam-mega"],
                   "메가 가능 종은 자기 스톤만 보인다", got: "\(alaMega)") && ok

        // 전용 Z크리스탈은 그 종에게만
        let mewSig = (m.itemsForSpecies[151] ?? []).compactMap { d -> Int? in
            if case .zCrystalSignature(let sid) = d.kind { return sid }
            return nil
        }
        ok = check(mewSig == [151], "전용 Z크리스탈은 그 종에게만 보인다",
                   got: "\(mewSig)") && ok

        // 6) Z크리스탈은 모든 종에게 보이므로, 맞는 타입 공격기가 없으면 낭비 경고가 떠야 한다.
        //    기술을 직접 지정해 확정적으로 만든다 (무작위 기술에 기대면 테스트가 흔들린다)
        for i in roster.indices { setItem(i, nil) }
        if let tackle = try? await PokeAPI.shared.move("tackle") {
            m.movesetsBySlot[roster[0].id] = [tackle]      // 노말 기술만
            // PokeAPI 는 "firium-z--held" 로 주지만 카탈로그는 실전 세팅과 같은
            // 정규형("firium-z")으로 등록한다 — 두 이름으로 두면 목록에 중복이 생긴다
            setItem(0, "firium-z")                   // 불꽃Z → 맞는 기술 없음
            let r = m.itemReadiness(for: roster[0])
            ok = check(r?.ok == false, "불꽃 공격기가 없으면 불꽃Z 는 작동 불가",
                       got: r?.headline ?? "nil") && ok
            ok = check(m.loadoutWarnings.contains { $0.severity == .waste },
                       "작동하지 않는 도구는 낭비 경고", got: "\(titles())") && ok

            setItem(0, "normalium-z")                // 노말Z → 몸통박치기와 맞음
            ok = check(m.itemReadiness(for: roster[0])?.ok == true,
                       "노말 공격기가 있으면 노말Z 는 작동") && ok
            ok = check(!m.loadoutWarnings.contains { $0.severity == .waste },
                       "작동하는 도구는 낭비 경고 없음", got: "\(titles())") && ok
        }

        // 7) Z크리스탈 2개 → 경고
        for i in roster.indices { setItem(i, nil) }
        setItem(0, "snorlium-z")         // 잠만보 전용Z
        setItem(1, "mewnium-z")          // 뮤 전용Z
        ok = check(m.loadoutWarnings.contains { $0.id == "z" },
                   "Z크리스탈 2개 → 경고", got: "\(titles())") && ok

        return ok
    }

    // MARK: 시나리오 빌더

    private static func battler(_ species: SpeciesDef, _ moves: [MoveDef],
                                item: ItemDef?, ability: AbilityDef?, tag: String) -> Battler {
        let slot = RosterSlot(id: tag, speciesID: species.id, nature: "serious",
                              rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
        return Battler.make(slot: slot, species: species, moves: moves, level: 50,
                            heldItem: item, ability: ability)
    }

    private static func engine(attacker: Int, defender: Int,
                               attMoves: [String], defMoves: [String],
                               attItem: String?, defItem: String?,
                               attAbility: String?, defAbility: String?,
                               chart: TypeChart, seed: UInt64 = 4242,
                               requireItems: Bool = true,
                               weakenDefender: Bool = false) async -> BattleEngine? {
        guard let aSp = try? await PokeAPI.shared.species(attacker),
              let dSp = try? await PokeAPI.shared.species(defender) else { return nil }
        var aM: [MoveDef] = [], dM: [MoveDef] = []
        for n in attMoves { if let m = try? await PokeAPI.shared.move(n) { aM.append(m) } }
        for n in defMoves { if let m = try? await PokeAPI.shared.move(n) { dM.append(m) } }
        guard !aM.isEmpty, !dM.isEmpty else { return nil }

        let aItem = attItem.flatMap { n in Optional(n) }
        let dItem = defItem.flatMap { n in Optional(n) }
        let ai = aItem == nil ? nil : await ItemCatalog.shared.item(aItem!)
        let di = dItem == nil ? nil : await ItemCatalog.shared.item(dItem!)
        let aa = attAbility == nil ? nil : await AbilityCatalog.shared.ability(attAbility!)
        let da = defAbility == nil ? nil : await AbilityCatalog.shared.ability(defAbility!)

        var a = battler(aSp, aM, item: ai, ability: aa, tag: "att")
        var d = battler(dSp, dM, item: di, ability: da, tag: "def")
        a.stats[.speed] = 999; d.stats[.speed] = 1
        // 기합의띠·옹골참은 "풀피에서 받는 일격" 이어야 발동한다.
        // 방어를 최저로 만들어 확정 치사를 보장한다 (안 그러면 난수에 따라 살아남아
        // 애초에 발동 조건이 아니게 되고, 테스트가 엉뚱하게 실패한다).
        if weakenDefender { d.stats[.defense] = 1; d.stats[.spDefense] = 1 }
        for i in a.moves.indices { a.moves[i].ppLeft = 99 }
        for i in d.moves.indices { d.moves[i].ppLeft = 99 }

        var rules = BattleRules(maxTeamSize: 1, level: 50)
        rules.requireItems = requireItems
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: [a], activeIndex: 0),
                                     SideState(playerName: "B", team: [d], activeIndex: 0)])
        st.phase = .awaitingMoves
        st.turn = 1
        var e = BattleEngine(state: st, chart: chart, seed: seed)
        // 폼 캐시
        var mc: [String: FormStats] = [:], gc: [String: FormStats] = [:]
        for f in aSp.megaForms { mc[f] = try? await PokeAPI.shared.form(named: f) }
        if let g = aSp.gmaxForm { gc[g] = try? await PokeAPI.shared.form(named: g) }
        e.megaCache = mc; e.gmaxCache = gc
        for (_, base) in FormTables.zMoveBase {
            for sfx in ["--physical", "--special"] {
                if let m = try? await PokeAPI.shared.move(base + sfx) { e.zMoveCache[base + sfx] = m }
            }
        }
        for (_, n) in FormTables.maxMove {
            if let m = try? await PokeAPI.shared.move(n) { e.maxMoveCache[n] = m }
        }
        if let g = try? await PokeAPI.shared.move(FormTables.maxGuard) { e.maxMoveCache[FormTables.maxGuard] = g }
        return e
    }

    // MARK: 검사들

    private static func gate(_ action: SpecialAction, species: Int, item: String?,
                             move: String = "tackle", expect: Bool, _ label: String,
                             _ chart: TypeChart) async -> Bool {
        guard var e = await engine(attacker: species, defender: 143,
                                   attMoves: [move], defMoves: ["splash"],
                                   attItem: item, defItem: nil,
                                   attAbility: nil, defAbility: nil, chart: chart) else {
            print("  ✗ \(label) — 준비 실패"); return false
        }
        e.resolveTurn(hostAction: .useMove(index: 0, special: action), guestAction: .useMove(index: 0))
        let s = e.state.sides[0]
        let happened: Bool
        switch action {
        case .mega:            happened = s.team[0].isMega && s.usedMega
        case .dynamax, .gmax:  happened = s.team[0].isDynamaxed && s.usedDynamax
        case .zMove:           happened = s.usedZMove
        }
        let pass = happened == expect
        print(pass ? "  ✓ \(label)" : "  ✗ \(label) — 기대 \(expect), 실제 \(happened)")
        if !pass { for l in e.state.log.prefix(4) { print("      \(l)") } }
        return pass
    }

    /// 도구를 끼운 쪽과 안 끼운 쪽의 데미지를 비교한다 (같은 시드).
    private static func damageCompare(_ item: String, move: String, _ chart: TypeChart,
                                      _ label: String, expectMore: Bool) async -> Bool {
        func dealt(_ it: String?) async -> Int? {
            guard var e = await engine(attacker: 143, defender: 143,
                                       attMoves: [move], defMoves: ["splash"],
                                       attItem: it, defItem: nil,
                                       attAbility: nil, defAbility: nil,
                                       chart: chart, seed: 31337) else { return nil }
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return before - e.state.sides[1].team[0].currentHP
        }
        guard let withItem = await dealt(item), let without = await dealt(nil) else {
            print("  ✗ \(label) — 준비 실패"); return false
        }
        let pass = expectMore ? withItem > without : withItem < without
        print(pass ? "  ✓ \(label) (\(without) → \(withItem))"
                   : "  ✗ \(label) — \(without) → \(withItem)")
        return pass
    }

    /// 확률 요소(명중·부가효과) 가 있으므로 여러 시드를 돌려 한 번이라도 성립하면 통과로 본다.
    private static func logContains(_ item: String, move: String, _ chart: TypeChart,
                                    needle: String, _ label: String,
                                    setup: ((inout Battler) -> Void)? = nil,
                                    onDefender: Bool = false,
                                    twoTurnsDifferentMove: Bool = false,
                                    weakenDefender: Bool = false,
                                    seeds: Int = 20) async -> Bool {
        let moves = twoTurnsDifferentMove ? [move, "tackle"] : [move]
        var lastLog: [String] = []
        for seed in 1...seeds {
            guard var e = await engine(attacker: 143, defender: 143,
                                       attMoves: moves, defMoves: ["splash"],
                                       attItem: onDefender ? nil : item,
                                       defItem: onDefender ? item : nil,
                                       attAbility: nil, defAbility: nil, chart: chart,
                                       seed: UInt64(seed) * 6151,
                                       weakenDefender: weakenDefender) else {
                print("  ✗ \(label) — 준비 실패"); return false
            }
            if let setup {
                var b = e.state.sides[onDefender ? 1 : 0].team[0]
                setup(&b)
                e.state.sides[onDefender ? 1 : 0].team[0] = b
            }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if twoTurnsDifferentMove, case .awaitingMoves = e.state.phase {
                e.resolveTurn(hostAction: .useMove(index: 1), guestAction: .useMove(index: 0))
            }
            lastLog = e.state.log
            if e.state.log.contains(where: { $0.contains(needle) }) {
                print("  ✓ \(label)")
                return true
            }
        }
        print("  ✗ \(label) — 시드 \(seeds)회 모두 로그에 \"\(needle)\" 없음")
        for l in lastLog.prefix(6) { print("      \(l)") }
        return false
    }

    private static func abilityLog(_ ability: String, move: String, _ chart: TypeChart,
                                   onDefender: Bool, needle: String, _ label: String,
                                   statusOnDefender: Ailment? = nil,
                                   expectNoNeedle: String? = nil,
                                   weakenDefender: Bool = false,
                                   seeds: Int = 20) async -> Bool {
        var lastLog: [String] = []
        for seed in 1...seeds {
            guard var e = await engine(attacker: 143, defender: 143,
                                       attMoves: [move], defMoves: ["splash"],
                                       attItem: nil, defItem: nil,
                                       attAbility: onDefender ? nil : ability,
                                       defAbility: onDefender ? ability : nil, chart: chart,
                                       seed: UInt64(seed) * 6151,
                                       weakenDefender: weakenDefender) else {
                print("  ✗ \(label) — 준비 실패"); return false
            }
            if let st = statusOnDefender {
                var b = e.state.sides[1].team[0]
                b.status = st
                if st == .toxic { b.toxicCounter = 1 }
                e.state.sides[1].team[0] = b
            }
            // 위협은 배틀 시작 시 발동하므로 beginBattle 을 거쳐야 한다
            if ability == "intimidate" {
                e.state.phase = .chooseLead
                e.beginBattle()
            }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            lastLog = e.state.log

            if let no = expectNoNeedle {
                // 부정 조건은 한 번만 확인하면 된다
                let bad = e.state.log.contains { $0.contains(no) }
                print(!bad ? "  ✓ \(label)" : "  ✗ \(label) — \"\(no)\" 가 나왔다")
                return !bad
            }
            if e.state.log.contains(where: { $0.contains(needle) }) {
                print("  ✓ \(label)")
                return true
            }
        }
        print("  ✗ \(label) — 시드 \(seeds)회 모두 로그에 \"\(needle)\" 없음")
        for l in lastLog.prefix(6) { print("      \(l)") }
        return false
    }

    private static func abilityDamage(_ ability: String, move: String, _ chart: TypeChart,
                                      onAttacker: Bool = false,
                                      expectZero: Bool = false,
                                      expectLess: Bool = false,
                                      expectMore: Bool = false,
                                      _ label: String) async -> Bool {
        func dealt(_ ab: String?) async -> Int? {
            guard var e = await engine(attacker: 143, defender: 143,
                                       attMoves: [move], defMoves: ["splash"],
                                       attItem: nil, defItem: nil,
                                       attAbility: onAttacker ? ab : nil,
                                       defAbility: onAttacker ? nil : ab,
                                       chart: chart, seed: 5150) else { return nil }
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return before - e.state.sides[1].team[0].currentHP
        }
        guard let withAb = await dealt(ability), let without = await dealt(nil) else {
            print("  ✗ \(label) — 준비 실패"); return false
        }
        let pass: Bool
        if expectZero      { pass = withAb == 0 }
        else if expectLess { pass = withAb < without }
        else               { pass = withAb > without }
        print(pass ? "  ✓ \(label) (\(without) → \(withAb))"
                   : "  ✗ \(label) — \(without) → \(withAb)")
        return pass
    }
}
