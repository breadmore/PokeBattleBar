import Foundation

/// `PokeBattleBar --abilitytest`
/// **등장 가능한 특성 중 몇 개가 실제로 배틀에 반영되는지** 측정한다.
///
/// PokeAPI 는 특성 효과를 산문으로만 주고, Showdown 조차 특성은 데이터가 아니라
/// JavaScript 함수다. 그래서 특성만은 하나씩 손으로 구현해야 하고,
/// "표시만" 인 것이 얼마나 남았는지 숫자로 알고 있어야 한다.
enum AbilityCoverageTest {

    static func run(full: Bool) async -> Bool {
        print("=== 특성 구현률 ===\n")
        var ok = true

        // 내 도감에서 실제로 나올 수 있는 종을 모은다
        let roster: [RosterSlot]
        if let st = try? CompanionStore.load() {
            roster = RosterSlot.roster(from: st)
        } else {
            roster = []
        }

        // PokeTokenBar 가 줄 수 있는 베이스 종 (5세대까지)
        var speciesIDs = Set(roster.map(\.speciesID))
        // 표본을 넓히려면 대표 종을 더 섞는다
        let extra = [3, 6, 9, 12, 25, 35, 52, 65, 68, 94, 95, 105, 112, 121, 130, 131,
                     143, 149, 151, 197, 208, 212, 214, 229, 232, 248, 260, 282, 289,
                     306, 317, 330, 350, 373, 376, 381, 385, 392, 395, 405, 445, 448,
                     460, 466, 467, 468, 472, 473, 479, 494, 497, 508, 526, 530, 534,
                     537, 545, 553, 560, 563, 567, 571, 579, 584, 589, 596, 601, 604,
                     609, 612, 615, 621, 623, 625, 630, 635, 637, 644, 649]
        speciesIDs.formUnion(full ? extra : Array(extra.prefix(30)))

        print("표본 종 \(speciesIDs.count)개에서 특성 수집 중…")
        var abilities: [String: AbilityDef] = [:]
        for id in speciesIDs.sorted() {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            for a in await AbilityCatalog.shared.abilities(for: sp) {
                abilities[a.name] = a
            }
        }

        let total = abilities.count
        let done = abilities.values.filter(\.isImplemented)
        let todo = abilities.values.filter { !$0.isImplemented }
        let pct = total == 0 ? 0 : done.count * 100 / total

        print()
        print("  등장 가능한 특성: \(total)종")
        print("  배틀에 반영됨:   \(done.count)종  (\(pct)%)")
        print("  표시만:         \(todo.count)종")
        print()

        ok = show(total > 50, "충분한 표본", "\(total)종") && ok
        ok = show(pct >= 60, "구현률 60% 이상", "\(pct)%") && ok

        if !todo.isEmpty {
            print("  -- 아직 반영 안 되는 특성 --")
            for a in todo.sorted(by: { $0.display < $1.display }).prefix(full ? 200 : 30) {
                print("    \(a.display.padding(toLength: 12, withPad: " ", startingAt: 0))"
                      + " \(a.shortEffect.prefix(72))")
            }
            if todo.count > (full ? 200 : 30) { print("    … 외 \(todo.count - 30)종") }
        }

        // 구현된 것들이 실제로 kind 를 가지는지 (매핑 오타 방지)
        print()
        var broken: [String] = []
        for a in done where AbilityCatalog.kind(for: a.name) == .none {
            broken.append(a.name)
        }
        ok = show(broken.isEmpty, "구현 표시된 특성은 전부 실제 효과가 있다",
                  broken.isEmpty ? "" : "\(broken)") && ok

        // 내 로스터 기준
        if !roster.isEmpty {
            print()
            print("  -- 내 로스터 --")
            for slot in roster {
                guard let sp = try? await PokeAPI.shared.species(slot.speciesID) else { continue }
                let list = await AbilityCatalog.shared.abilities(for: sp)
                let impl = list.filter(\.isImplemented).count
                print("    \(sp.display.padding(toLength: 8, withPad: " ", startingAt: 0))"
                      + " \(impl)/\(list.count) 반영"
                      + " — " + list.map {
                          $0.display + ($0.isImplemented ? "" : "(표시만)")
                      }.joined(separator: ", "))
            }
        }

        // **배선까지 확인한다.**
        //
        // 표에 넣는 것과 엔진이 실제로 그걸 보는 것은 다른 일이다.
        // 실제로 용의턱은 표에 있었지만 이름이 틀려 한 번도 실행되지 않았다.
        ok = await liveEffectCheck() && ok

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    /// 새로 넣은 특성 몇 개를 **실제 배틀에서** 돌려본다.
    private static func liveEffectCheck() async -> Bool {
        print("\n  -- 엔진 배선 확인 --")
        guard let chart = try? await PokeAPI.shared.typeChart(),
              let tackle = try? await PokeAPI.shared.move("tackle"),
              let splash = try? await PokeAPI.shared.move("splash"),
              let ember = try? await PokeAPI.shared.move("ember"),
              let growl = try? await PokeAPI.shared.move("growl") else {
            return show(false, "배선 확인 준비")
        }
        var ok = true

        /// 특성을 붙여 한 턴 돌리고 로그와 최종 상태를 돌려준다.
        func run(ability: String, kind: AbilityKind, myMove: MoveDef, foeMove: MoveDef,
                 foeAbility: String? = nil) async -> (log: [String], me: Battler, foe: Battler)? {
            guard let uSp = try? await PokeAPI.shared.species(143),
                  let fSp = try? await PokeAPI.shared.species(151) else { return nil }
            func make(_ sp: SpeciesDef, _ ms: [MoveDef], _ tag: String,
                      _ ab: AbilityDef?, speed: Int) -> Battler {
                let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                      rarity: "common", isShiny: false, origin: .dex,
                                      fullyEvolved: true)
                var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50,
                                     ability: ab)
                for i in b.moves.indices { b.moves[i].ppLeft = 99 }
                b.stats[.speed] = speed
                b.maxHP = 400; b.currentHP = 400
                return b
            }
            let mine = AbilityDef(name: ability, koName: ability,
                                  shortEffect: "", kind: kind)
            let theirs = foeAbility.map {
                AbilityDef(name: $0, koName: $0, shortEffect: "",
                           kind: AbilityCatalog.kind(for: $0))
            }
            var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                                 sides: [SideState(playerName: "나",
                                                   team: [make(uSp, [myMove], "h", mine, speed: 999)],
                                                   activeIndex: 0),
                                         SideState(playerName: "상대",
                                                   team: [make(fSp, [foeMove], "g", theirs, speed: 1)],
                                                   activeIndex: 0)])
            st.phase = .chooseLead
            var e = BattleEngine(state: st, chart: chart, seed: 909)
            e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
            e.beginBattle()
            guard case .awaitingMoves = e.state.phase else { return nil }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return (e.state.log, e.state.sides[0].team[0], e.state.sides[1].team[0])
        }

        // 에어레이트 — 몸통박치기(노말)가 비행 타입이 된다
        if let r = await run(ability: "aerilate",
                             kind: .moveTypeConversion(from: .normal, to: .flying, multiplier: 1.2),
                             myMove: tackle, foeMove: splash) {
            ok = show(r.log.contains { $0.contains("비행 타입이 되었다") },
                      "에어레이트가 기술 타입을 바꾼다") && ok
        } else { ok = show(false, "에어레이트") && ok }

        // 변환자재 — 쓴 기술의 타입으로 자신이 변한다
        if let r = await run(ability: "protean", kind: .userTypeMatchesMove,
                             myMove: ember, foeMove: splash) {
            ok = show(r.me.types == [.fire], "변환자재로 자기 타입이 바뀐다",
                      "\(r.me.types.map(\.ko))") && ok
        } else { ok = show(false, "변환자재") && ok }

        // 일렉트릭메이커 — 등장 시 필드가 깔린다
        if let r = await run(ability: "electric-surge", kind: .terrainOnEntry(.electric),
                             myMove: splash, foeMove: splash) {
            ok = show(r.log.contains { $0.contains("일렉트릭") },
                      "일렉트릭메이커가 필드를 만든다") && ok
        } else { ok = show(false, "일렉트릭메이커") && ok }

        // 불요의검 — 등장 시 공격이 오른다
        if let r = await run(ability: "intrepid-sword", kind: .boostOnEntry(.attack, 1),
                             myMove: splash, foeMove: splash) {
            ok = show((r.me.stages[.attack] ?? 0) >= 1, "불요의검이 등장 시 공격을 올린다",
                      "\(r.me.stages[.attack] ?? 0)단계") && ok
        } else { ok = show(false, "불요의검") && ok }

        // 여왕의위엄 — 선공 기술(전광석화)이 막힌다
        if let quick = try? await PokeAPI.shared.move("quick-attack"),
           let r = await run(ability: "no-guard", kind: .noGuard,
                             myMove: quick, foeMove: splash,
                             foeAbility: "queenly-majesty") {
            ok = show(r.log.contains { $0.contains("선공 기술은 통하지 않는다") },
                      "여왕의위엄이 선공 기술을 막는다") && ok
        } else { ok = show(false, "여왕의위엄") && ok }

        // 매지컬아머 — 능력 하락이 상대에게 되돌아간다
        if let r = await run(ability: "no-guard", kind: .noGuard,
                             myMove: growl, foeMove: splash,
                             foeAbility: "mirror-armor") {
            ok = show((r.me.stages[.attack] ?? 0) < 0,
                      "매지컬아머가 능력 하락을 되돌린다",
                      "내 공격 \(r.me.stages[.attack] ?? 0)단계") && ok
        } else { ok = show(false, "매지컬아머") && ok }

        // 재앙 4종 — 상대 방어가 0.75배가 되어 데미지가 늘어난다
        if let plain = await run(ability: "no-guard", kind: .noGuard,
                                 myMove: tackle, foeMove: splash),
           let ruined = await run(ability: "sword-of-ruin", kind: .ruin(.defense, 0.75),
                                  myMove: tackle, foeMove: splash) {
            let a = 400 - plain.foe.currentHP
            let b = 400 - ruined.foe.currentHP
            ok = show(b > a, "재의검이 상대 방어를 깎는다", "\(a) → \(b)") && ok
        } else { ok = show(false, "재의검") && ok }

        // 옷무늬 — 첫 공격이 막힌다
        if let r = await run(ability: "no-guard", kind: .noGuard,
                             myMove: tackle, foeMove: splash,
                             foeAbility: "disguise") {
            ok = show(r.foe.currentHP == r.foe.maxHP && r.foe.shieldUsed,
                      "옷무늬가 첫 공격을 막는다",
                      "\(r.foe.currentHP)/\(r.foe.maxHP)") && ok
        } else { ok = show(false, "옷무늬") && ok }

        return ok
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }
}
