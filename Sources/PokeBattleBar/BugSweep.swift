import Foundation

/// `PokeBattleBar --bugsweep [--battles N] [--verbose]`
///
/// 무작위 배틀을 대량으로 굴리면서 **매 턴마다 불변식을 검사한다.**
/// 개별 기능 테스트는 "의도한 동작이 되는가" 를 보지만, 이건
/// "어떤 조합에서도 절대 깨지면 안 되는 규칙" 을 본다 — 포켓몬 엔진에서 흔한 버그 유형이다.
enum BugSweep {

    struct Violation: Hashable {
        var rule: String
        var detail: String
    }

    static func run(battles: Int, verbose: Bool) async -> Bool {
        print("=== 불변식 버그 스윕 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else {
            print("✗ 상성표 실패"); return false
        }
        await ItemCatalog.shared.loadAll()

        // 특성·도구·폼이 다양한 종을 섞는다
        let pool = [3, 6, 9, 25, 65, 68, 87, 94, 99, 130, 131, 143, 149, 208, 317, 448]
        print("종 \(pool.count)개 / 배틀 \(battles)회 / 전 기능 ON\n")

        var violations: [Violation: Int] = [:]
        var turnsTotal = 0, finished = 0, stalled = 0
        var rng = SystemRandomNumberGenerator()

        for battleNo in 1...battles {
            guard var e = await makeBattle(pool: pool, chart: chart,
                                           seed: UInt64(battleNo) * 2654435761, rng: &rng) else {
                print("✗ 배틀 \(battleNo) 준비 실패"); return false
            }

            var turns = 0
            let cap = 300
            // 한 번 쓰러진 개체가 다시 살아나는지 추적한다 (다이맥스 해제 부활 버그 회귀 방지)
            var everFainted: Set<String> = []
            while turns < cap {
                turns += 1
                switch e.state.phase {
                case .awaitingMoves:
                    let h = action(for: .host, e.state, &rng)
                    let g = action(for: .guest, e.state, &rng)
                    e.resolveTurn(hostAction: h, guestAction: g)
                case .awaitingReplacement(let needs):
                    for raw in needs {
                        guard let side = BattleSide(rawValue: raw) else { continue }
                        let alive = e.state.side(side).aliveIndices
                        guard let pick = alive.randomElement(using: &rng) else { continue }
                        e.applyReplacement(side, teamIndex: pick)
                    }
                    // 직전 턴 스텝이 남아 있으면 UI 가 그것을 다시 재생한다 —
                    // 방금 쓰러진 포켓몬이 한 번 더 쓰러지는 연출이 된다
                    if !e.state.steps.isEmpty {
                        violations[Violation(rule: "교체 뒤에 직전 턴 재생 스텝이 남았다",
                                             detail: "steps=\(e.state.steps.count)"),
                                   default: 0] += 1
                    }
                case .awaitingPivot(let pending):
                    for raw in pending {
                        guard let side = BattleSide(rawValue: raw) else { continue }
                        let alive = e.state.side(side).aliveIndices
                            .filter { $0 != e.state.side(side).activeIndex }
                        guard let pick = alive.randomElement(using: &rng) else { continue }
                        e.applyPivot(side, teamIndex: pick)
                    }
                    if !e.state.steps.isEmpty {
                        violations[Violation(rule: "피벗 뒤에 직전 턴 재생 스텝이 남았다",
                                             detail: "steps=\(e.state.steps.count)"),
                                   default: 0] += 1
                    }
                case .chooseLead:
                    e.setLead(.host, index: 0); e.setLead(.guest, index: 0); e.beginBattle()
                case .finished:
                    break
                }

                for v in check(e.state) { violations[v, default: 0] += 1 }

                for (i, side) in e.state.sides.enumerated() {
                    for (j, b) in side.team.enumerated() {
                        let key = "\(i)-\(j)"
                        if b.isFainted { everFainted.insert(key) }
                        else if everFainted.contains(key) {
                            violations[Violation(rule: "쓰러진 포켓몬이 되살아났다",
                                                 detail: "side\(i) team[\(j)] \(b.name) "
                                                       + "HP=\(b.currentHP)/\(b.maxHP)"),
                                       default: 0] += 1
                            everFainted.remove(key)
                        }
                    }
                }
                if case .finished = e.state.phase { break }
            }
            turnsTotal += turns
            if case .finished = e.state.phase { finished += 1 } else {
                stalled += 1
                violations[Violation(rule: "배틀이 \(cap)턴 안에 끝나지 않음",
                                     detail: "phase=\(e.state.phase)"), default: 0] += 1
                if verbose { for l in e.state.log.suffix(10) { print("      \(l)") } }
            }
        }

        // 결과
        print("배틀 \(battles)회 / 총 \(turnsTotal)턴 / 정상 종료 \(finished) / 미종료 \(stalled)")
        print("평균 \(turnsTotal / max(1, battles))턴\n")

        if violations.isEmpty {
            print("✓ 불변식 위반 없음 — 검사한 규칙:")
            for r in ruleList { print("    · \(r)") }
            return true
        }

        print("✗ 불변식 위반 \(violations.values.reduce(0, +))건:")
        for (v, count) in violations.sorted(by: { $0.value > $1.value }) {
            print("  [\(count)회] \(v.rule)")
            print("           \(v.detail)")
        }
        return false
    }

    static let ruleList = [
        "HP 는 0 이상 maxHP 이하",
        "PP 는 0 이상 정의된 최대치 이하",
        "능력치 랭크는 -6 이상 6 이하 (명중·회피 포함)",
        "쓰러진 포켓몬이 활성일 수 없다 (교체 대기 중 제외)",
        "활성 인덱스가 팀 범위를 벗어나지 않는다",
        "교체 대기 단계는 실제로 활성이 쓰러졌을 때만",
        "종료 단계는 한쪽이 전멸했을 때만",
        "다이맥스 중이 아니면 maxHP 는 원래 값과 같다",
        "다이맥스 남은 턴은 0 이상 3 이하",
        "맹독 카운터는 0 이상 15 이하",
        "잠듦 턴수는 0 이상 4 이하",
        "혼란 턴수는 0 이상 5 이하",
        "구애 고정 인덱스는 기술 범위 안",
        "턴 수는 감소하지 않는다",
        "배틀은 유한 턴 안에 끝난다",
        "피벗(유턴) 단계는 활성이 살아 있고 벤치에 낼 포켓몬이 있을 때만",
        "묶기 턴수는 0 이상 6 이하",
        "쓰러진 포켓몬은 절대 되살아나지 않는다",
        "교체 뒤에 직전 턴 재생 스텝이 남았다",
        "피벗 뒤에 직전 턴 재생 스텝이 남았다"
    ]

    // MARK: 불변식 검사

    private static func check(_ st: BattleState) -> [Violation] {
        var out: [Violation] = []
        func bad(_ rule: String, _ detail: String) { out.append(Violation(rule: rule, detail: detail)) }

        for (i, side) in st.sides.enumerated() {
            let who = "side\(i)(\(side.playerName))"

            if !side.team.indices.contains(side.activeIndex) {
                bad("활성 인덱스가 팀 범위를 벗어남",
                    "\(who) activeIndex=\(side.activeIndex) team=\(side.team.count)")
                continue
            }

            for (j, b) in side.team.enumerated() {
                let tag = "\(who) team[\(j)] \(b.name)"

                if b.currentHP < 0 || b.currentHP > b.maxHP {
                    bad("HP 범위 위반", "\(tag) \(b.currentHP)/\(b.maxHP)")
                }
                if b.maxHP <= 0 { bad("maxHP 가 0 이하", "\(tag) maxHP=\(b.maxHP)") }

                for (k, m) in b.moves.enumerated() {
                    if m.ppLeft < 0 || m.ppLeft > m.def.pp {
                        bad("PP 범위 위반", "\(tag) 기술[\(k)] \(m.def.display) \(m.ppLeft)/\(m.def.pp)")
                    }
                }

                for (stat, stage) in b.stages where stage < -6 || stage > 6 {
                    bad("능력치 랭크 범위 위반", "\(tag) \(stat.ko)=\(stage)")
                }
                if b.accuracyStage < -6 || b.accuracyStage > 6 {
                    bad("명중 랭크 범위 위반", "\(tag) \(b.accuracyStage)")
                }
                if b.evasionStage < -6 || b.evasionStage > 6 {
                    bad("회피 랭크 범위 위반", "\(tag) \(b.evasionStage)")
                }

                if b.dynamaxTurnsLeft < 0 || b.dynamaxTurnsLeft > FormTables.dynamaxTurns {
                    bad("다이맥스 턴 범위 위반", "\(tag) \(b.dynamaxTurnsLeft)")
                }
                if !b.isDynamaxed, b.baseMaxHP > 0, b.maxHP != b.baseMaxHP {
                    bad("다이맥스가 끝났는데 maxHP 가 원복되지 않음",
                        "\(tag) maxHP=\(b.maxHP) base=\(b.baseMaxHP)")
                }
                if b.toxicCounter < 0 || b.toxicCounter > 15 {
                    bad("맹독 카운터 범위 위반", "\(tag) \(b.toxicCounter)")
                }
                if b.sleepTurns < 0 || b.sleepTurns > 4 {
                    bad("잠듦 턴수 범위 위반", "\(tag) \(b.sleepTurns)")
                }
                if b.confusionTurns < 0 || b.confusionTurns > 5 {
                    bad("혼란 턴수 범위 위반", "\(tag) \(b.confusionTurns)")
                }
                if b.trappedTurns < 0 || b.trappedTurns > 6 {
                    bad("묶기 턴수 범위 위반", "\(tag) \(b.trappedTurns)")
                }
                if let lock = b.lockedMoveIndex, !b.moves.indices.contains(lock) {
                    bad("구애 고정 인덱스가 범위를 벗어남", "\(tag) \(lock)")
                }
                if b.status == .sleep, b.sleepTurns == 0, !b.isFainted {
                    // 잠듦인데 카운터가 0 이면 영원히 못 깨어난다
                    bad("잠듦 상태인데 카운터가 0", tag)
                }
            }
        }

        // 단계별 정합성
        switch st.phase {
        case .awaitingMoves:
            for (i, side) in st.sides.enumerated()
            where side.team.indices.contains(side.activeIndex) && side.active.isFainted {
                bad("행동 단계인데 활성이 쓰러져 있음",
                    "side\(i) \(side.active.name)")
            }
        case .awaitingReplacement(let needs):
            for raw in needs {
                guard let s = BattleSide(rawValue: raw), st.sides.indices.contains(raw) else {
                    bad("교체 대기 대상이 잘못됨", "raw=\(raw)"); continue
                }
                let side = st.side(s)
                if side.team.indices.contains(side.activeIndex), !side.active.isFainted {
                    bad("교체 대기인데 활성이 살아 있음", "side\(raw) \(side.active.name)")
                }
                if side.remaining == 0 {
                    bad("교체할 포켓몬이 없는데 교체 대기", "side\(raw)")
                }
            }
        case .finished(let w):
            let a = st.sides[0].remaining, b = st.sides[1].remaining
            if a != 0 && b != 0 { bad("종료됐는데 양쪽 다 생존", "A=\(a) B=\(b)") }
            if let w, st.sides[w].remaining == 0 {
                bad("전멸한 쪽이 승자로 기록됨", "winner=\(w)")
            }
        case .awaitingPivot(let pending):
            for raw in pending {
                guard let s = BattleSide(rawValue: raw), st.sides.indices.contains(raw) else {
                    bad("피벗 대상이 잘못됨", "raw=\(raw)"); continue
                }
                let side = st.side(s)
                if side.team.indices.contains(side.activeIndex), side.active.isFainted {
                    bad("피벗 단계인데 활성이 쓰러져 있음", "side\(raw)")
                }
                let benchAlive = side.aliveIndices.contains { $0 != side.activeIndex }
                if !benchAlive {
                    bad("낼 포켓몬이 없는데 피벗 단계", "side\(raw)")
                }
            }
        case .chooseLead:
            break
        }
        return out
    }

    // MARK: 배틀 생성

    private static func action(for side: BattleSide, _ st: BattleState,
                               _ rng: inout SystemRandomNumberGenerator) -> BattleAction {
        let me = st.side(side)
        let b = me.active

        // 가끔 특수 변신을 선언한다 (모든 경로를 밟게 하려고)
        var special: SpecialAction?
        if Int.random(in: 1...6, using: &rng) == 1 {
            var pool: [SpecialAction] = [.dynamax, .zMove]
            if let f = b.megaForms.first { pool.append(.mega(form: f)) }
            if b.gmaxForm != nil { pool.append(.gmax) }
            special = pool.randomElement(using: &rng)
        }
        // 구애로 고정됐으면 그 기술만
        if let lock = b.lockedMoveIndex, b.moves.indices.contains(lock), b.moves[lock].usable {
            return .useMove(index: lock, special: special)
        }
        let usable = b.moves.indices.filter { b.moves[$0].usable }
        let idx = usable.randomElement(using: &rng) ?? 0
        return .useMove(index: idx, special: special)
    }

    private static func makeBattle(pool: [Int], chart: TypeChart, seed: UInt64,
                                   rng: inout SystemRandomNumberGenerator) async -> BattleEngine? {
        func team(_ tag: String, size: Int) async -> [Battler]? {
            var out: [Battler] = []
            var picks: [Int] = []
            while picks.count < size { picks.append(pool.randomElement(using: &rng)!) }
            for (i, id) in picks.enumerated() {
                guard let sp = try? await PokeAPI.shared.species(id) else { return nil }
                let slot = RosterSlot(id: "\(tag)-\(i)", speciesID: id,
                                      nature: Nature.koNames.keys.sorted()[i % 25],
                                      rarity: "common", isShiny: false,
                                      origin: .dex, fullyEvolved: true)
                let moves = await MovesetStore.shared.moveset(for: slot, species: sp)
                guard !moves.isEmpty else { return nil }
                // 도구·특성도 무작위로 붙인다
                let items = await ItemCatalog.shared.available(forSpecies: sp)
                let item = Bool.random(using: &rng) ? items.randomElement(using: &rng) : nil
                let abils = await AbilityCatalog.shared.abilities(for: sp)
                let ability = abils.randomElement(using: &rng)
                out.append(Battler.make(slot: slot, species: sp, moves: moves, level: 50,
                                        heldItem: item, ability: ability))
            }
            return out
        }
        guard let a = await team("A", size: Int.random(in: 1...4, using: &rng)),
              let b = await team("B", size: Int.random(in: 1...4, using: &rng)) else { return nil }

        var rules = BattleRules(maxTeamSize: 6, level: 50)
        rules.requireItems = Bool.random(using: &rng)
        rules.allowSwitching = false
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: a, activeIndex: 0),
                                     SideState(playerName: "B", team: b, activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: seed)

        // 폼 / 변환 기술 캐시
        for t in a + b {
            for f in t.megaForms where e.megaCache[f] == nil {
                e.megaCache[f] = try? await PokeAPI.shared.form(named: f)
            }
            if let g = t.gmaxForm, e.gmaxCache[g] == nil {
                e.gmaxCache[g] = try? await PokeAPI.shared.form(named: g)
            }
        }
        for (_, base) in FormTables.zMoveBase {
            for sfx in ["--physical", "--special"] {
                if let m = try? await PokeAPI.shared.move(base + sfx) { e.zMoveCache[base + sfx] = m }
            }
        }
        for (_, n) in FormTables.maxMove {
            if let m = try? await PokeAPI.shared.move(n) { e.maxMoveCache[n] = m }
        }
        if let g = try? await PokeAPI.shared.move(FormTables.maxGuard) {
            e.maxMoveCache[FormTables.maxGuard] = g
        }
        return e
    }
}
