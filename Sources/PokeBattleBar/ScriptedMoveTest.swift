import Foundation

/// 데이터에 구조화돼 있지 않아 손으로 구현한 기술들의 **행동** 검증.
///
/// 이름만 목록에 적어두는 것으로는 아무것도 증명되지 않는다 (실제로 그렇게
/// 적어놨다가 대부분이 미구현인 것을 뒤늦게 알았다). 그래서 배틀을 실제로
/// 돌려 기대한 결과가 나오는지 본다.
enum ScriptedMoveTest {

    static func run(verbose: Bool) async -> Bool {
        print("=== 손으로 구현한 기술 검증 ===\n")
        var ok = true

        guard let chart = try? await PokeAPI.shared.typeChart() else {
            print("  ✗ 상성표 로드 실패"); return false
        }

        // MARK: 잠자기
        print("-- 잠자기 --")
        if let r = await probe(move: "rest", user: 143, foe: 143, chart: chart,
                              setup: { b in b.currentHP = b.maxHP / 2 }) {
            ok = show(r.user.currentHP == r.user.maxHP, "HP 가 완전히 회복된다",
                      "\(r.user.currentHP)/\(r.user.maxHP)") && ok
            ok = show(r.user.status == .sleep, "자신이 잠든다", "\(r.user.status)") && ok
            ok = show(r.user.sleepTurns == 2, "2턴 잠든다", "\(r.user.sleepTurns)") && ok
            ok = show(r.log.contains { $0.contains("잠들어 체력을 회복") },
                      "로그에 남는다",
                      r.log.first { $0.contains("잠들어 체력을 회복") } ?? "없음") && ok
        } else { ok = show(false, "잠자기 실행") && ok }

        // HP 가 가득이면 실패해야 한다
        if let r = await probe(move: "rest", user: 143, foe: 143, chart: chart) {
            ok = show(r.user.status != .sleep, "HP 가 가득이면 잠자기는 실패한다") && ok
        }

        // MARK: 저주 — 고스트
        print("\n-- 저주 (고스트) --")
        if let r = await probe(move: "curse", user: 94, foe: 143, chart: chart) {
            ok = show(r.user.currentHP < r.user.maxHP, "고스트는 자기 HP 를 깎는다",
                      "\(r.user.currentHP)/\(r.user.maxHP)") && ok
            ok = show(r.foe.cursed, "상대가 저주에 걸린다") && ok
        } else { ok = show(false, "저주 실행") && ok }

        // MARK: 저주 — 고스트가 아닌 경우
        print("\n-- 저주 (고스트 아님) --")
        if let r = await probe(move: "curse", user: 143, foe: 94, chart: chart) {
            ok = show((r.user.stages[.attack] ?? 0) == 1, "공격이 오른다",
                      "\(r.user.stages[.attack] ?? 0)") && ok
            ok = show((r.user.stages[.defense] ?? 0) == 1, "방어가 오른다") && ok
            ok = show((r.user.stages[.speed] ?? 0) == -1, "스피드가 떨어진다") && ok
            ok = show(!r.foe.cursed, "상대는 저주에 걸리지 않는다") && ok
            ok = show(r.user.currentHP == r.user.maxHP, "HP 는 줄지 않는다") && ok
        } else { ok = show(false, "저주(비고스트) 실행") && ok }

        // MARK: 배북
        print("\n-- 배북 --")
        if let r = await probe(move: "belly-drum", user: 143, foe: 143, chart: chart) {
            ok = show((r.user.stages[.attack] ?? 0) == 6, "공격이 최대(+6)가 된다",
                      "\(r.user.stages[.attack] ?? 0)") && ok
            let expected = r.user.maxHP - max(1, r.user.maxHP / 2)
            ok = show(r.user.currentHP == expected, "최대 HP 의 절반을 쓴다",
                      "\(r.user.currentHP) (기대 \(expected))") && ok
        } else { ok = show(false, "배북 실행") && ok }

        // 체력이 부족하면 실패
        if let r = await probe(move: "belly-drum", user: 143, foe: 143, chart: chart,
                              setup: { b in b.currentHP = 5 }) {
            ok = show((r.user.stages[.attack] ?? 0) == 0, "체력이 부족하면 배북은 실패한다") && ok
            ok = show(r.user.currentHP == 5, "실패하면 HP 도 줄지 않는다", "\(r.user.currentHP)") && ok
        }

        // MARK: 대타출동
        print("\n-- 대타출동 --")
        if let r = await probe(move: "substitute", user: 143, foe: 143, chart: chart) {
            let cost = max(1, r.user.maxHP / 4)
            ok = show(r.user.substituteHP == cost, "인형 HP = 최대 HP 의 1/4",
                      "\(r.user.substituteHP ?? -1) (기대 \(cost))") && ok
            ok = show(r.user.currentHP == r.user.maxHP - cost, "그만큼 HP 를 쓴다") && ok
        } else { ok = show(false, "대타출동 실행") && ok }

        // 인형이 데미지를 대신 받는가
        if let r = await twoTurn(first: "substitute", then: "tackle",
                                user: 143, foe: 143, chart: chart) {
            ok = show(r.user.substituteHP != nil || r.log.contains { $0.contains("인형이 부서졌") },
                      "인형이 공격을 받아낸다",
                      r.log.filter { $0.contains("인형") }.joined(separator: " / ")) && ok
            let cost = max(1, r.user.maxHP / 4)
            ok = show(r.user.currentHP == r.user.maxHP - cost,
                      "인형이 있는 동안 본체 HP 는 줄지 않는다",
                      "\(r.user.currentHP)/\(r.user.maxHP)") && ok
        }

        // MARK: 아픔나누기
        print("\n-- 아픔나누기 --")
        if let r = await probe(move: "pain-split", user: 94, foe: 143, chart: chart,
                              setup: { b in b.currentHP = 10 }) {
            ok = show(r.user.currentHP > 10, "적은 쪽이 회복된다",
                      "\(r.user.currentHP)") && ok
            ok = show(r.foe.currentHP < r.foe.maxHP, "많은 쪽이 줄어든다",
                      "\(r.foe.currentHP)/\(r.foe.maxHP)") && ok
        } else { ok = show(false, "아픔나누기 실행") && ok }

        // MARK: 타입을 바꾸는 기술
        print("\n-- 타입 변화 --")
        if let r = await probe(move: "soak", user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.types == [.water], "물놀이는 상대를 물 타입으로 만든다",
                      "\(r.foe.types.map(\.ko))") && ok
        }
        if let r = await probe(move: "trick-or-treat", user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.types.contains(.ghost), "할로윈은 고스트를 추가한다",
                      "\(r.foe.types.map(\.ko))") && ok
            ok = show(r.foe.types.count == 2, "원래 타입은 남는다") && ok
        }
        if let r = await probe(move: "forests-curse", user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.types.contains(.grass), "숲의저주는 풀을 추가한다",
                      "\(r.foe.types.map(\.ko))") && ok
        }
        if let r = await probe(move: "reflect-type", user: 143, foe: 94, chart: chart) {
            ok = show(Set(r.user.types) == Set(r.foe.types),
                      "미러타입은 상대와 같은 타입이 된다",
                      "\(r.user.types.map(\.ko)) vs \(r.foe.types.map(\.ko))") && ok
        }

        // MARK: 2턴 기술
        print("\n-- 모으는 기술 (솔라빔) --")
        if let r = await probe(move: "solar-beam", user: 94, foe: 143, chart: chart) {
            ok = show(r.user.isCharging, "첫 턴에는 모으기만 한다") && ok
            ok = show(r.foe.currentHP == r.foe.maxHP, "첫 턴에는 데미지가 없다",
                      "\(r.foe.currentHP)/\(r.foe.maxHP)") && ok
            ok = show(r.log.contains { $0.contains("빛을 흡수") }, "모으는 문구가 나온다",
                      r.log.first { $0.contains("빛을 흡수") } ?? "없음") && ok
        } else { ok = show(false, "솔라빔 실행") && ok }

        if let r = await twoTurn(first: "solar-beam", then: "solar-beam",
                                user: 94, foe: 143, chart: chart) {
            ok = show(!r.user.isCharging, "두 번째 턴에 발사된다") && ok
            ok = show(r.foe.currentHP < r.foe.maxHP, "두 번째 턴에 데미지가 들어간다",
                      "\(r.foe.currentHP)/\(r.foe.maxHP)") && ok
        }

        print("\n-- 숨는 기술 (땅속) --")
        if let r = await probe(move: "dig", user: 143, foe: 94, chart: chart) {
            ok = show(r.user.chargeHidden, "땅속에 숨는다") && ok
        }

        // MARK: 반동 기술
        print("\n-- 반동 기술 (파괴광선) --")
        if let r = await probe(move: "hyper-beam", user: 143, foe: 143, chart: chart) {
            ok = show(r.user.mustRechargeTurns == 1, "쓴 턴에 반동이 예약된다",
                      "\(r.user.mustRechargeTurns)") && ok
            ok = show(r.foe.currentHP < r.foe.maxHP, "그 턴에는 데미지가 들어간다") && ok
        } else { ok = show(false, "파괴광선 실행") && ok }

        if let r = await twoTurn(first: "hyper-beam", then: "hyper-beam",
                                user: 143, foe: 143, chart: chart) {
            ok = show(r.log.contains { $0.contains("반동으로 움직일 수 없다") },
                      "다음 턴에는 움직이지 못한다",
                      r.log.first { $0.contains("반동으로") } ?? "없음") && ok
            ok = show(r.user.mustRechargeTurns == 0, "반동이 풀린다") && ok
        }

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    // MARK: 도구

    struct Probe {
        var user: Battler
        var foe: Battler
        var log: [String]
    }

    /// 한 턴만 돌린다. 내가 `move` 를, 상대는 튀어오르기(아무 일 없음)를 쓴다.
    private static func probe(move: String, user: Int, foe: Int, chart: TypeChart,
                              setup: ((inout Battler) -> Void)? = nil) async -> Probe? {
        await battle(moves: [move], user: user, foe: foe, chart: chart, setup: setup)
    }

    /// 두 턴 돌린다 (모으기·반동 확인용)
    private static func twoTurn(first: String, then second: String,
                                user: Int, foe: Int, chart: TypeChart) async -> Probe? {
        await battle(moves: [first, second], user: user, foe: foe, chart: chart, setup: nil)
    }

    private static func battle(moves: [String], user: Int, foe: Int, chart: TypeChart,
                               setup: ((inout Battler) -> Void)?) async -> Probe? {
        guard let uSp = try? await PokeAPI.shared.species(user),
              let fSp = try? await PokeAPI.shared.species(foe),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }

        var defs: [MoveDef] = []
        for n in Set(moves) {
            guard let m = try? await PokeAPI.shared.move(n) else { return nil }
            defs.append(m)
        }
        // 인형 검증용으로 탁쳐서떨구기 대신 몸통박치기를 쓴다
        var foeMoves: [MoveDef] = [splash]
        if moves.contains("tackle"), let t = try? await PokeAPI.shared.move("tackle") {
            foeMoves = [t]
        }

        func make(_ sp: SpeciesDef, _ ms: [MoveDef], _ tag: String) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            return b
        }

        var me = make(uSp, defs, "me")
        me.stats[.speed] = 999          // 내가 먼저 움직이게
        setup?(&me)
        var them = make(fSp, foeMoves, "foe")
        them.stats[.speed] = 1

        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나", team: [me], activeIndex: 0),
                                     SideState(playerName: "상대", team: [them], activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 99)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        for name in moves {
            guard case .awaitingMoves = e.state.phase else { break }
            guard let idx = e.state.sides[0].team[0].moves.firstIndex(where: { $0.def.name == name })
            else { break }
            e.resolveTurn(hostAction: .useMove(index: idx), guestAction: .useMove(index: 0))
        }
        return Probe(user: e.state.sides[0].team[0],
                     foe: e.state.sides[1].team[0],
                     log: e.state.log)
    }

    private static func show(_ c: Bool, _ label: String, _ detail: String = "") -> Bool {
        print("  \(c ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
        return c
    }
}
