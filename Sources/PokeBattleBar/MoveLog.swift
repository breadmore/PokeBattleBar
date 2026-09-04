import Foundation

/// 기술 하나를 몇 턴 돌려보고 **로그를 그대로 찍는다.**
///
///     PokeBattleBar --movelog fly
///     PokeBattleBar --movelog dream-eater --turns 2 --foe-move rest
///
/// 검증(assert)이 아니라 눈으로 보기 위한 도구다. "왜 안 때리지?" 같은 질문은
/// 로그를 보면 대개 한 번에 답이 나온다.
enum MoveLog {
    static func run(move: String, turns: Int, foeMove: String, userSpeed: Int,
                    extraMove: String? = nil) async -> Bool {
        guard let chart = try? await PokeAPI.shared.typeChart() else {
            print("상성표를 불러올 수 없습니다"); return false
        }
        guard let mv = try? await PokeAPI.shared.move(move),
              let fm = try? await PokeAPI.shared.move(foeMove) else {
            print("기술을 불러올 수 없습니다: \(move) / \(foeMove)"); return false
        }
        // 잠꼬대처럼 **다른 기술을 골라 쓰는** 기술은 후보가 있어야 확인이 된다
        var myMoves = [mv]
        if let extraMove, let em = try? await PokeAPI.shared.move(extraMove) {
            myMoves.append(em)
        }
        // 갸라도스(130) vs 뮤(151) — 뮤는 어떤 타입에도 무효가 없다
        guard let uSp = try? await PokeAPI.shared.species(130),
              let fSp = try? await PokeAPI.shared.species(151) else {
            print("종을 불러올 수 없습니다"); return false
        }
        func make(_ sp: SpeciesDef, _ ms: [MoveDef], _ tag: String, speed: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            b.maxHP = 500; b.currentHP = 500
            return b
        }
        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make(uSp, myMoves, "h", speed: userSpeed)],
                                               activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make(fSp, [fm], "g", speed: 100)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 4242)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        print("=== \(mv.display) (\(move)) — \(turns)턴 ===")
        print("  내 속도 \(userSpeed) / 상대 속도 100 · 상대는 \(fm.display)")
        print("  charge=\(mv.isCharge) 몸을숨김=\(mv.chargeHides) 위력=\(mv.power.map(String.init) ?? "없음")\n")

        var shown = 0
        for t in 1...turns {
            guard case .awaitingMoves = e.state.phase else {
                print("-- \(t)턴: 진행할 수 없다 (phase=\(e.state.phase))"); break
            }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            let me = e.state.sides[0].team[0]
            let foe = e.state.sides[1].team[0]
            print("-- \(t)턴 --")
            for line in e.state.log[shown...] { print("   \(line)") }
            shown = e.state.log.count
            print("   [내 HP \(me.currentHP)/\(me.maxHP)"
                  + " · 모으는중=\(me.chargingMoveIndex.map(String.init) ?? "없음")"
                  + " · 숨음=\(me.chargeHidden)]")
            print("   [상대 HP \(foe.currentHP)/\(foe.maxHP) · 상태=\(foe.status)]\n")
        }
        return true
    }
}
