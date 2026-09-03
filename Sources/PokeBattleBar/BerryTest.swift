import Foundation

/// `PokeBattleBar --berrytest`
/// 나무열매와 3차 특성(먹보·긴장감·해감액·저주받은바디·트레이스·픽업·무게)을 검증한다.
enum BerryTest {
    static func run() async -> Bool {
        print("=== 나무열매 · 확장 특성 검증 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else { return false }
        await ItemCatalog.shared.loadAll()
        var ok = true

        // MARK: 데이터
        print("-- 나무열매 데이터 --")
        let all = await ItemCatalog.shared.items
        let berries = all.values.filter(\.isBerry)
        ok = show(berries.count >= 35, "나무열매 적재", "\(berries.count)종") && ok
        for (slug, ko) in [("sitrus-berry", "회복"), ("lum-berry", "상태이상 치료"),
                           ("yache-berry", "타입 방어"), ("liechi-berry", "궁지 능력 상승"),
                           ("leppa-berry", "PP 회복")] {
            if let b = all[slug] {
                print("  ✓ \(b.display.padding(toLength: 10, withPad: " ", startingAt: 0))"
                      + "\(ko) — \(b.shortEffect.prefix(58))")
            } else { print("  ✗ \(slug) 없음"); ok = false }
        }
        var resistCount = 0, pinchCount = 0, cureCount = 0
        for b in berries {
            switch b.kind {
            case .berryTypeResist: resistCount += 1
            case .berryPinchBoost: pinchCount += 1
            case .berryCure: cureCount += 1
            default: break
            }
        }
        ok = show(resistCount >= 17, "타입 방어 열매", "\(resistCount)종") && ok
        ok = show(pinchCount == 5, "궁지 능력 열매", "\(pinchCount)종") && ok
        ok = show(cureCount >= 6, "상태이상 치료 열매", "\(cureCount)종") && ok

        // MARK: 실제 발동
        print("\n-- 열매 발동 --")
        ok = await berryHeals("sitrus-berry", chart, "자뭉열매 — HP 절반에서 회복") && ok
        ok = await berryCures("lum-berry", .burn, chart, "리샘열매 — 화상 치료") && ok
        ok = await berryCures("rawst-berry", .burn, chart, "화상치료열매") && ok
        ok = await berryPinch("liechi-berry", chart, "치리열매 — 궁지에서 공격 상승") && ok
        ok = await berryResist(chart) && ok
        ok = await berryConsumedOnce(chart) && ok

        // MARK: 열매 관련 특성
        print("\n-- 열매 특성 --")
        ok = await gluttonyEarlier(chart) && ok
        ok = await unnerveBlocks(chart) && ok

        // MARK: 3차 특성
        print("\n-- 확장 특성 --")
        ok = await liquidOoze(chart) && ok
        ok = await cursedBody(chart) && ok
        ok = await traceCopies(chart) && ok

        // MARK: 무게
        print("\n-- 무게 --")
        ok = weightTable() && ok
        ok = await weightMoveWorks(chart) && ok

        // MARK: 더블 전용 구분
        print("\n-- 더블배틀 전용 구분 --")
        if let tele = await AbilityCatalog.shared.ability("telepathy") {
            ok = show(tele.isDoublesOnly, "텔레파시는 더블 전용으로 표시") && ok
            ok = show(!tele.isImplemented, "더블 전용은 구현으로 세지 않는다") && ok
            ok = show(tele.statusTag == "더블 전용", "꼬리표", tele.statusTag ?? "-") && ok
        }
        if let glut = await AbilityCatalog.shared.ability("gluttony") {
            ok = show(glut.isImplemented && !glut.isDoublesOnly, "먹보는 구현됨") && ok
        }

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }

    /// 열매를 낀 1대1 엔진. 방어측(1번)이 열매를 든다.
    private static func setup(_ berry: String?, chart: TypeChart, seed: UInt64,
                              attMove: String = "splash", defAbility: String? = nil,
                              attAbility: String? = nil,
                              defHPFraction: Double = 1.0) async -> BattleEngine? {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: [attMove], defMoves: ["splash"],
                                           chart: chart, seed: seed) else { return nil }
        if let berry, let it = await ItemCatalog.shared.item(berry) {
            e.state.sides[1].team[0].heldItem = it
        }
        if let defAbility, let ab = await AbilityCatalog.shared.ability(defAbility) {
            e.state.sides[1].team[0].ability = ab
        }
        if let attAbility, let ab = await AbilityCatalog.shared.ability(attAbility) {
            e.state.sides[0].team[0].ability = ab
        }
        if defHPFraction < 1.0 {
            let b = e.state.sides[1].team[0]
            e.state.sides[1].team[0].currentHP = max(1, Int(Double(b.maxHP) * defHPFraction))
        }
        return e
    }

    private static func berryHeals(_ berry: String, _ chart: TypeChart, _ label: String) async -> Bool {
        guard var e = await setup(berry, chart: chart, seed: 101, defHPFraction: 0.4) else {
            return show(false, label, "준비 실패")
        }
        let before = e.state.sides[1].team[0].currentHP
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let after = e.state.sides[1].team[0].currentHP
        let consumed = e.state.sides[1].team[0].itemConsumed
        return show(after > before && consumed, label, "\(before) → \(after), 소비=\(consumed)")
    }

    private static func berryCures(_ berry: String, _ ail: Ailment,
                                   _ chart: TypeChart, _ label: String) async -> Bool {
        guard var e = await setup(berry, chart: chart, seed: 202) else {
            return show(false, label, "준비 실패")
        }
        e.state.sides[1].team[0].status = ail
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let cured = e.state.sides[1].team[0].status == .none
        return show(cured, label, cured ? "" : "\(e.state.sides[1].team[0].status.ko) 남음")
    }

    private static func berryPinch(_ berry: String, _ chart: TypeChart, _ label: String) async -> Bool {
        guard var e = await setup(berry, chart: chart, seed: 303, defHPFraction: 0.2) else {
            return show(false, label, "준비 실패")
        }
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let stage = e.state.sides[1].team[0].stages[.attack] ?? 0
        return show(stage > 0, label, "공격 랭크 \(stage)")
    }

    /// 타입 방어 열매 — 효과가 굉장한 기술 피해를 반감
    private static func berryResist(_ chart: TypeChart) async -> Bool {
        func dealt(_ withBerry: Bool) async -> Int? {
            // 격투 기술 → 노말(잠만보) 2배. 격투 방어 열매(chople) 로 반감돼야 한다
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["brick-break"], defMoves: ["splash"],
                                               chart: chart, seed: 4040) else { return nil }
            if withBerry, let it = await ItemCatalog.shared.item("chople-berry") {
                e.state.sides[1].team[0].heldItem = it
            }
            e.state.sides[1].team[0].maxHP = 99999
            e.state.sides[1].team[0].currentHP = 99999
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return before - e.state.sides[1].team[0].currentHP
        }
        guard let w = await dealt(true), let n = await dealt(false) else {
            return show(false, "격투방어열매 — 효과 굉장한 피해 반감", "준비 실패")
        }
        return show(w < n, "격투방어열매 — 효과 굉장한 피해 반감", "\(n) → \(w)")
    }

    /// 열매는 한 번만 먹는다
    private static func berryConsumedOnce(_ chart: TypeChart) async -> Bool {
        guard var e = await setup("sitrus-berry", chart: chart, seed: 505, defHPFraction: 0.3) else {
            return show(false, "열매는 한 번만", "준비 실패")
        }
        var eats = 0
        for _ in 0..<6 {
            guard case .awaitingMoves = e.state.phase else { break }
            let before = e.state.log.count
            e.state.sides[1].team[0].currentHP = max(1, e.state.sides[1].team[0].maxHP / 4)
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            eats += e.state.log[before...].filter { $0.contains("자뭉열매") }.count
        }
        return show(eats == 1, "열매는 한 번만 먹는다", "\(eats)회")
    }

    /// 먹보 — 1/4 대신 1/2 에서 먹는다
    private static func gluttonyEarlier(_ chart: TypeChart) async -> Bool {
        func ateAt(_ fraction: Double, gluttony: Bool) async -> Bool {
            guard var e = await setup("liechi-berry", chart: chart, seed: 606,
                                      defAbility: gluttony ? "gluttony" : nil,
                                      defHPFraction: fraction) else { return false }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return e.state.sides[1].team[0].itemConsumed
        }
        let normalAtHalf = await ateAt(0.45, gluttony: false)
        let gluttonAtHalf = await ateAt(0.45, gluttony: true)
        var ok = show(!normalAtHalf, "먹보 없으면 절반에선 안 먹는다") 
        ok = show(gluttonAtHalf, "먹보면 절반에서 먹는다") && ok
        return ok
    }

    /// 긴장감 — 상대가 열매를 못 먹는다
    private static func unnerveBlocks(_ chart: TypeChart) async -> Bool {
        guard var e = await setup("sitrus-berry", chart: chart, seed: 707,
                                  attAbility: "unnerve", defHPFraction: 0.3) else {
            return show(false, "긴장감", "준비 실패")
        }
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let ate = e.state.sides[1].team[0].itemConsumed
        return show(!ate, "긴장감 — 상대가 열매를 먹지 못한다", ate ? "먹어버렸다" : "")
    }

    /// 해감액 — 흡수가 오히려 피해
    private static func liquidOoze(_ chart: TypeChart) async -> Bool {
        for seed in 1...12 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["giga-drain"], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 71),
                  let ab = await AbilityCatalog.shared.ability("liquid-ooze") else { continue }
            e.state.sides[1].team[0].ability = ab
            e.state.sides[1].team[0].maxHP = 99999
            e.state.sides[1].team[0].currentHP = 99999
            e.state.sides[0].team[0].currentHP = e.state.sides[0].team[0].maxHP / 2
            let before = e.state.sides[0].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            let after = e.state.sides[0].team[0].currentHP
            if e.state.log.contains(where: { $0.contains("해감액") }) {
                return show(after < before, "해감액 — 흡수가 피해로 돌아온다", "\(before) → \(after)")
            }
        }
        return show(false, "해감액", "12시드 모두 미발동")
    }

    /// 저주받은바디 — 맞은 기술이 봉인된다
    private static func cursedBody(_ chart: TypeChart) async -> Bool {
        for seed in 1...40 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["body-slam", "hyper-voice"],
                                               defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 83),
                  let ab = await AbilityCatalog.shared.ability("cursed-body") else { continue }
            e.state.sides[1].team[0].ability = ab
            e.state.sides[1].team[0].maxHP = 99999
            e.state.sides[1].team[0].currentHP = 99999
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if e.state.log.contains(where: { $0.contains("봉인됐다") }) {
                let a = e.state.sides[0].team[0]
                var ok = show(a.disabledTurns > 0 && a.disabledMoveIndex == 0,
                              "저주받은바디 — 기술 봉인", "남은 \(a.disabledTurns)턴")
                // 봉인된 기술을 쓰려 하면 막힌다
                if case .awaitingMoves = e.state.phase {
                    let before = e.state.log.count
                    e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                    ok = show(e.state.log[before...].contains { $0.contains("봉인되어 있다") },
                              "봉인된 기술은 쓸 수 없다") && ok
                }
                return ok
            }
        }
        return show(false, "저주받은바디", "40시드 모두 미발동")
    }

    /// 트레이스 — 상대 특성 복사
    private static func traceCopies(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["splash"], defMoves: ["splash"],
                                           chart: chart, seed: 909),
              let trace = await AbilityCatalog.shared.ability("trace"),
              let thick = await AbilityCatalog.shared.ability("thick-fat") else {
            return show(false, "트레이스", "준비 실패")
        }
        e.state.sides[0].team[0].ability = trace
        e.state.sides[1].team[0].ability = thick
        e.state.phase = .chooseLead
        e.beginBattle()
        let copied = e.state.sides[0].team[0].ability?.name
        return show(copied == "thick-fat", "트레이스 — 상대 특성 복사", copied ?? "nil")
    }

    private static func weightTable() -> Bool {
        var ok = true
        // 안다리걸기 — 상대 무게로 위력이 정해진다
        ok = show(BattleEngine.weightBasedPower(move: "low-kick", attackerWeight: 100,
                                                targetWeight: 50) == 20,
                  "안다리걸기 5kg 상대 → 위력 20") && ok
        ok = show(BattleEngine.weightBasedPower(move: "low-kick", attackerWeight: 100,
                                                targetWeight: 4600) == 120,
                  "안다리걸기 460kg(잠만보) → 위력 120") && ok
        // 헤비봄버 — 무게 비율
        ok = show(BattleEngine.weightBasedPower(move: "heavy-slam", attackerWeight: 4600,
                                                targetWeight: 500) == 120,
                  "헤비봄버 9배 무거우면 위력 120") && ok
        ok = show(BattleEngine.weightBasedPower(move: "heavy-slam", attackerWeight: 500,
                                                targetWeight: 4600) == 40,
                  "헤비봄버 가벼우면 위력 40") && ok
        ok = show(BattleEngine.weightBasedPower(move: "tackle", attackerWeight: 1,
                                                targetWeight: 1) == nil,
                  "무게 기술이 아니면 nil") && ok
        return ok
    }

    /// 무게 기술이 실제 배틀에서 데미지를 내는가
    private static func weightMoveWorks(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 68, def: 143,      // 괴력몬 → 잠만보(460kg)
                                           attMoves: ["low-kick"], defMoves: ["splash"],
                                           chart: chart, seed: 1212) else {
            return show(false, "안다리걸기 실전", "준비 실패")
        }
        e.state.sides[1].team[0].maxHP = 99999
        e.state.sides[1].team[0].currentHP = 99999
        let before = e.state.sides[1].team[0].currentHP
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let dealt = before - e.state.sides[1].team[0].currentHP
        var ok = show(dealt > 0, "안다리걸기가 데미지를 낸다 (무게 위력)", "\(dealt)")
        ok = show(e.state.sides[1].team[0].weight == 4600, "무게가 실제로 실려 있다",
                  "\(e.state.sides[1].team[0].weight) 헥토그램") && ok
        return ok
    }
}
