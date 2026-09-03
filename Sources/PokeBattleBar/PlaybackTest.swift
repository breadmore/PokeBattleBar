import Foundation

/// 턴 재생 연출 검증.
///
/// 회귀 방지 대상: 새 상태를 `battle` 에 먼저 대입하면 재생 오버라이드가
/// 아직 없는 한 프레임 동안 **턴이 다 끝난 상태**가 그려진다. 그 프레임에서
/// 양쪽 HP 가 한꺼번에 떨어지므로 "둘 다 맞는 연출이 한 번 나오고 나서
/// 다시 순서대로 재생" 되는 것처럼 보였다.
enum PlaybackTest {

    @MainActor
    static func run() async -> Bool {
        print("=== 턴 재생 연출 ===\n")
        var ok = true
        func show(_ cond: Bool, _ label: String, _ detail: String = "") -> Bool {
            print("  \(cond ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
            return cond
        }

        guard let chart = try? await PokeAPI.shared.typeChart(),
              let snorlax = try? await PokeAPI.shared.species(143),
              let mew = try? await PokeAPI.shared.species(151),
              let tackle = try? await PokeAPI.shared.move("tackle") else {
            print("  ✗ 준비 실패"); return false
        }

        func team(_ sp: SpeciesDef, _ tag: String, count: Int = 2) -> [Battler] {
            (0..<count).map { i in
                let slot = RosterSlot(id: "\(tag)-\(i)", speciesID: sp.id, nature: "serious",
                                      rarity: "common", isShiny: false, origin: .dex,
                                      fullyEvolved: true)
                var b = Battler.make(slot: slot, species: sp, moves: [tackle], level: 50)
                b.moves[0].ppLeft = 99
                return b
            }
        }

        let rules = BattleRules(maxTeamSize: 2, level: 50)
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "나", team: team(snorlax, "h"), activeIndex: 0),
                                     SideState(playerName: "상대", team: team(mew, "g"), activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 7)
        e.setLead(.host, index: 0)
        e.setLead(.guest, index: 0)
        e.beginBattle()

        let m = AppModel()
        m.rules = rules
        m.mySide = .host
        m.present(e.state)      // 배틀 시작 — 재생할 스텝이 없다

        let startHostHP = m.displayTeam(.host).map(\.currentHP)
        let startGuestHP = m.displayTeam(.guest).map(\.currentHP)

        // 양쪽이 서로를 때리는 턴 — 둘 다 HP 가 줄어든다
        e.resolveTurn(hostAction: .useMove(index: 0),
                      guestAction: .useMove(index: 0))
        let resolvedHostHP = e.state.sides[0].team.map(\.currentHP)
        let resolvedGuestHP = e.state.sides[1].team.map(\.currentHP)

        // 테스트가 헛돌지 않는지 먼저 확인한다 — 실제로 양쪽이 다 맞아야 의미가 있다
        ok = show(!e.state.steps.isEmpty, "재생할 스텝이 생겼다",
                  "\(e.state.steps.count)단계") && ok
        ok = show(resolvedHostHP != startHostHP && resolvedGuestHP != startGuestHP,
                  "이 턴에는 양쪽이 다 맞는다 (검사가 유효)",
                  "나 \(startHostHP)→\(resolvedHostHP) / 상대 \(startGuestHP)→\(resolvedGuestHP)") && ok

        m.present(e.state)

        // 핵심: 재생을 시작한 직후 화면은 **턴 시작 시점**이어야 한다
        let shownHost = m.displayTeam(.host).map(\.currentHP)
        let shownGuest = m.displayTeam(.guest).map(\.currentHP)
        ok = show(shownHost == startHostHP,
                  "재생 시작 시 내 HP 는 턴 시작 값",
                  "화면 \(shownHost) / 턴시작 \(startHostHP) / 결과 \(resolvedHostHP)") && ok
        ok = show(shownGuest == startGuestHP,
                  "재생 시작 시 상대 HP 는 턴 시작 값",
                  "화면 \(shownGuest) / 턴시작 \(startGuestHP) / 결과 \(resolvedGuestHP)") && ok
        ok = show(shownHost != resolvedHostHP || shownGuest != resolvedGuestHP,
                  "턴 결과 상태가 한 프레임도 노출되지 않는다") && ok

        // 로그도 턴 시작 시점까지만 보여야 한다 (결과를 미리 읽히면 안 된다)
        let addedLines = e.state.steps.reduce(0) { $0 + $1.log.count }
        ok = show(m.displayLog.count == e.state.log.count - addedLines,
                  "로그도 턴 시작 지점까지만 보인다",
                  "\(m.displayLog.count) / 전체 \(e.state.log.count)") && ok

        // 스텝이 없는 갱신(교체 등)은 곧바로 반영돼야 한다 — 멈춰 보이면 안 된다
        if case .awaitingReplacement = e.state.phase {} else {
            var e2 = e
            e2.state.steps = []
            m.present(e2.state)
            ok = show(m.displayTeam(.host).map(\.currentHP) == e2.state.sides[0].team.map(\.currentHP),
                      "재생할 것이 없으면 바로 최신 상태를 보여준다") && ok
        }

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }
}
