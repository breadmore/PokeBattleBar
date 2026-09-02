import Foundation

/// `PokeBattleBar --selftest` 로 실행하는 헤드리스 검증.
/// UI·네트워크 없이 배틀 엔진만 끝까지 돌려서 불변식을 확인한다.
enum SelfTest {

    static func run(speciesA: [Int], speciesB: [Int], level: Int, verbose: Bool) async -> Bool {
        print("=== PokeBattleBar 자체 검증 ===")
        print("A팀 \(speciesA) vs B팀 \(speciesB) / Lv.\(level)\n")

        let chart: TypeChart
        do {
            chart = try await PokeAPI.shared.typeChart()
        } catch {
            print("✗ 상성표 로드 실패: \(error.localizedDescription)")
            return false
        }

        // 상성표 정합성 확인 (몇 개 알려진 값)
        var ok = true
        ok = expect(chart.multiplier(attack: .water, defenders: [.fire]), 2.0, "물→불꽃", &ok) && ok
        ok = expect(chart.multiplier(attack: .electric, defenders: [.ground]), 0.0, "전기→땅", &ok) && ok
        ok = expect(chart.multiplier(attack: .grass, defenders: [.water, .flying]), 1.0, "풀→물/비행", &ok) && ok
        ok = expect(chart.multiplier(attack: .ice, defenders: [.dragon, .flying]), 4.0, "얼음→드래곤/비행", &ok) && ok

        // 팀 구성
        guard let teamA = await buildTeam(speciesA, tag: "A", level: level),
              let teamB = await buildTeam(speciesB, tag: "B", level: level) else { return false }

        print("\n-- A팀 --"); dump(teamA)
        print("\n-- B팀 --"); dump(teamB)

        // 스탯 공식 검증 (원작 공식, 개체값 31 / 노력치 0 / Lv.50):
        //   HP  = floor((2*100 + 31) * 50/100) + 50 + 10 = 115 + 60 = 175
        //   공격 = floor((2*100 + 31) * 50/100) + 5       = 115 + 5  = 120
        // 실제 게임 값과 대조: 잠만보(종족값160) 235, 후딘(55) 130 — 둘 다 일치.
        let sanity = Battler.computeStats(
            base: SpeciesDef(id: 0, name: "t", koName: "t", types: [.normal],
                             baseStats: Dictionary(uniqueKeysWithValues: Stat.allCases.map { ($0, 100) }),
                             learnableMoves: []),
            nature: Nature.named("serious"), level: 50)
        ok = expect(Double(sanity.hp), 175.0, "Lv.50 종족값100 HP", &ok) && ok
        ok = expect(Double(sanity.others[.attack] ?? 0), 120.0, "Lv.50 종족값100 공격", &ok) && ok

        // 배틀 실행
        var st = BattleState(rules: BattleRules(maxTeamSize: 6, level: level),
                             sides: [SideState(playerName: "A", team: teamA, activeIndex: 0),
                                     SideState(playerName: "B", team: teamB, activeIndex: 0)])
        st.phase = .chooseLead
        var engine = BattleEngine(state: st, chart: chart, seed: 0xC0FFEE)
        engine.setLead(.host, index: 0)
        engine.setLead(.guest, index: 0)
        engine.beginBattle()

        var guard_ = 0
        let turnCap = 400
        var rng = SystemRandomNumberGenerator()

        while guard_ < turnCap {
            guard_ += 1
            switch engine.state.phase {
            case .awaitingMoves:
                let h = randomMove(engine.state.side(.host).active, &rng)
                let g = randomMove(engine.state.side(.guest).active, &rng)
                engine.resolveTurn(hostAction: h, guestAction: g)
            case .awaitingReplacement(let needs):
                for raw in needs {
                    guard let side = BattleSide(rawValue: raw) else { continue }
                    let alive = engine.state.side(side).aliveIndices
                    guard let pick = alive.randomElement(using: &rng) else { continue }
                    engine.applyReplacement(side, teamIndex: pick)
                }
            case .finished, .chooseLead:
                break
            }
            if case .finished = engine.state.phase { break }
            if case .chooseLead = engine.state.phase { break }

            // 불변식: HP 는 0..max 범위를 벗어나선 안 된다
            for s in [BattleSide.host, .guest] {
                for b in engine.state.side(s).team {
                    if b.currentHP < 0 || b.currentHP > b.maxHP {
                        print("✗ HP 범위 위반: \(b.name) \(b.currentHP)/\(b.maxHP)")
                        ok = false
                    }
                }
            }
        }

        if verbose {
            print("\n-- 배틀 로그 --")
            for l in engine.state.log { print("  " + l) }
        } else {
            print("\n-- 배틀 로그 (마지막 25줄) --")
            for l in engine.state.log.suffix(25) { print("  " + l) }
        }

        print("\n-- 결과 --")
        print("  로그 \(engine.state.log.count)줄 / 턴 \(engine.state.turn) / 루프 \(guard_)회")

        if case .finished(let w) = engine.state.phase {
            let name = w == nil ? "무승부" : engine.state.sides[w!].playerName + " 승"
            print("  종료: \(name) ✓")
        } else {
            print("  ✗ \(turnCap)회 안에 끝나지 않았습니다 (phase=\(engine.state.phase))")
            ok = false
        }

        // 종료 시 한쪽은 전멸해 있어야 한다
        if case .finished = engine.state.phase {
            let a = engine.state.side(.host).remaining
            let b = engine.state.side(.guest).remaining
            if a != 0 && b != 0 {
                print("  ✗ 종료됐는데 양쪽 다 생존 (A:\(a) B:\(b))")
                ok = false
            } else {
                print("  잔존 A:\(a) B:\(b) ✓")
            }
        }

        // 조사 회귀 검사 — 받침 처리가 깨지면 여기서 잡힌다
        let badParticles = ["스피드이", "드은", "방어은", "어이 ", "HP이"]
        var particleOK = true
        for line in engine.state.log {
            for bad in badParticles where line.contains(bad) {
                print("  ✗ 조사 오류: \(line)  [\(bad)]")
                particleOK = false
                ok = false
            }
        }
        if particleOK { print("  조사 검사 통과 ✓") }

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    // MARK: 헬퍼

    private static func expect(_ got: Double, _ want: Double, _ label: String, _ ok: inout Bool) -> Bool {
        if abs(got - want) < 0.0001 {
            print("  ✓ \(label) = \(got)")
            return true
        }
        print("  ✗ \(label): 기대 \(want), 실제 \(got)")
        ok = false
        return false
    }

    private static func buildTeam(_ ids: [Int], tag: String, level: Int) async -> [Battler]? {
        var team: [Battler] = []
        for (i, id) in ids.enumerated() {
            do {
                let sp = try await PokeAPI.shared.species(id)
                let slot = RosterSlot(id: "\(tag)-\(i)-\(id)", speciesID: id,
                                      nature: Nature.koNames.keys.sorted()[i % 25],
                                      rarity: "common", isShiny: false,
                                      origin: .dex, fullyEvolved: true)
                let moves = await MovesetStore.shared.moveset(for: slot, species: sp)
                if moves.isEmpty {
                    print("✗ \(sp.display) 기술을 하나도 못 받았습니다")
                    return nil
                }
                team.append(Battler.make(slot: slot, species: sp, moves: moves, level: level))
            } catch {
                print("✗ 종 \(id) 로드 실패: \(error.localizedDescription)")
                return nil
            }
        }
        return team
    }

    private static func dump(_ team: [Battler]) {
        for b in team {
            let statLine = [Stat.attack, .defense, .spAttack, .spDefense, .speed]
                .map { "\($0.ko) \(b.stat($0))" }.joined(separator: " ")
            print("  \(b.name) (\(b.types.map(\.ko).joined(separator: "/"))) Lv.\(b.level) \(b.natureName)")
            print("    HP \(b.maxHP) / \(statLine)")
            print("    기술: " + b.moves.map { "\($0.def.display)(\($0.def.type.ko)/\($0.def.power.map(String.init) ?? "-")/PP\($0.def.pp))" }.joined(separator: ", "))
        }
    }

    private static func randomMove(_ b: Battler, _ rng: inout SystemRandomNumberGenerator) -> BattleAction {
        let usable = b.moves.indices.filter { b.moves[$0].usable }
        // PP 가 전부 떨어지면 원작의 발버둥 대신 0번 기술을 재사용한다 (검증용)
        return .useMove(index: usable.randomElement(using: &rng) ?? 0)
    }
}
