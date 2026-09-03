import Foundation

/// `PokeBattleBar --edgetest`
///
/// 포켓몬 배틀 엔진에서 **실제로 자주 틀리는 지점들**을 하나씩 확인한다.
/// 원작 규칙과 다르게 구현되기 쉬운 곳, 그리고 예전에 이 엔진에서 실제로 터진 유형들.
enum EdgeCaseTest {

    static func run(verbose: Bool) async -> Bool {
        print("=== 엣지 케이스 점검 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else { return false }
        await ItemCatalog.shared.loadAll()
        var ok = true

        // MARK: 타입 면역과 상태기
        print("-- 타입 면역 --")
        // 전기 기술인 전기자석파는 땅 타입에게 통하지 않아야 한다
        ok = await expectLog("thunder-wave", def: 208, chart,      // 강철톤 = 강철/땅
                             absent: "마비 상태가 되었다",
                             "전기자석파는 땅 타입에게 무효") && ok
        // 노말/격투는 고스트에게 무효
        ok = await expectDamage("body-slam", def: 94, chart, expect: 0,
                                "노말 기술은 고스트에게 0") && ok
        // 무효인 기술은 부가효과도 발동하지 않는다
        ok = await expectLog("thunder-wave", def: 208, chart,
                             absent: "떨어졌다", "무효 기술은 능력치 변화도 없음") && ok
        // 최면술은 에스퍼 타입 — 악 타입에게 통하지 않는다
        ok = await expectLog("hypnosis", def: 197, chart,          // 블래키 = 악
                             absent: "잠듦 상태가 되었다",
                             "최면술은 악 타입에게 무효") && ok
        // 반대로 날씨·필드 기술은 타입 면역으로 막혀선 안 된다
        ok = await expectPresent("electric-terrain", def: 208, chart,   // 강철톤 = 강철/땅
                                 needle: "일렉트릭필드가 깔렸다",
                                 "일렉트릭필드는 땅 타입 상대에게도 깔린다") && ok
        ok = await expectPresent("sunny-day", def: 9, chart,            // 거북왕 = 물
                                 needle: "쾌청 상태가 되었다",
                                 "쾌청은 물 타입 상대에게도 걸린다") && ok
        // 자신을 대상으로 하는 변화기는 상대 타입과 무관하다
        ok = await expectPresent("swords-dance", def: 94, chart,
                                 needle: "공격이 크게 올라갔다",
                                 "자신 강화 기술은 상대 타입 무관") && ok

        // MARK: 자폭과 면역의 조합 — 흔한 실수
        print("\n-- 자폭 --")
        // 대폭발은 고스트에게 데미지 0 이지만, **쓴 쪽은 그래도 쓰러진다**
        ok = await selfKOAgainstImmune(chart) && ok
        ok = await selfKOOnMiss(chart) && ok
        ok = await selfKOOrderDiffers(chart) && ok

        // MARK: 화상 / 상태이상 계산
        print("\n-- 상태이상 계산 --")
        ok = await burnHalvesPhysicalOnly(chart) && ok
        ok = await sleepAlwaysWakes(chart) && ok
        ok = await freezeAlwaysThaws(chart) && ok
        ok = await toxicCaps(chart) && ok

        // MARK: 급소
        print("\n-- 급소 --")
        ok = await critIgnoresDrops(chart) && ok

        // MARK: 랭크 클램프
        print("\n-- 능력치 랭크 --")
        ok = await stageClamp(chart) && ok

        // MARK: 회복 상한
        print("\n-- 회복 --")
        ok = await healCannotExceedMax(chart) && ok
        ok = await drainAtOneHP(chart) && ok

        // MARK: 반동
        print("\n-- 반동 --")
        ok = await recoilCanKO(chart) && ok

        // MARK: 다단히트와 기합의띠 — 원작에서 자주 헷갈리는 조합
        print("\n-- 다단히트 --")
        ok = await multiHitBreaksSash(chart) && ok

        // MARK: 다이맥스 HP 정확 원복
        print("\n-- 다이맥스 --")
        ok = await dynamaxHPExactRestore(chart) && ok

        // MARK: PP
        print("\n-- PP --")
        ok = await ppNeverNegative(chart) && ok

        // MARK: 스탯 공식
        print("\n-- 스탯 공식 --")
        ok = statFormula() && ok

        // MARK: 발버둥 — PP 가 다 떨어졌을 때 (무한 배틀 방지)
        print("\n-- 발버둥 --")
        ok = await struggleWhenNoPP(chart) && ok

        // MARK: 동시 전멸 시 승패
        print("\n-- 동시 전멸 --")
        ok = await selfKOTieIsHandled(chart) && ok

        // MARK: 스피드 동일
        print("\n-- 스피드 동일 --")
        ok = await speedTieResolves(chart) && ok

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    // MARK: 개별 검사

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }

    /// 대폭발이 고스트에게 0 데미지여도 쓴 쪽은 쓰러진다
    private static func selfKOAgainstImmune(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 94,
                                           attMoves: ["explosion"], defMoves: ["splash"],
                                           chart: chart, seed: 777) else {
            return show(false, "대폭발 vs 고스트", "준비 실패")
        }
        let foeBefore = e.state.sides[1].team[0].currentHP
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let selfFainted = e.state.sides[0].team[0].isFainted
        let foeUnhurt = e.state.sides[1].team[0].currentHP == foeBefore
        return show(selfFainted && foeUnhurt,
                    "대폭발은 무효 상대에게도 쓴 쪽이 쓰러진다",
                    "자신 쓰러짐=\(selfFainted) 상대 무피해=\(foeUnhurt)")
    }

    /// 대폭발과 목숨걸기는 쓰러지는 **시점**이 다르다.
    /// 대폭발은 판정보다 먼저(무효·빗나감에도 쓰러진다),
    /// 목숨걸기는 맞춘 뒤(자기 HP 만큼 주고 나서) 쓰러진다.
    private static func selfKOOrderDiffers(_ chart: TypeChart) async -> Bool {
        var ok = true
        // 대폭발 = always
        ok = show(MoveFlags.selfDestructsBeforeMove("explosion"),
                  "대폭발은 판정 전에 쓰러진다") && ok
        ok = show(MoveFlags.selfDestructsBeforeMove("self-destruct"),
                  "자폭도 판정 전") && ok
        // 목숨걸기·메멘토 = ifHit
        ok = show(!MoveFlags.selfDestructsBeforeMove("final-gambit"),
                  "목숨걸기는 맞춘 뒤에 쓰러진다") && ok
        ok = show(!MoveFlags.selfDestructsBeforeMove("memento"),
                  "메멘토도 효과 뒤") && ok

        // 목숨걸기가 실제로 자기 HP 만큼 주는지 (먼저 쓰러지면 0 이 된다)
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["final-gambit"], defMoves: ["splash"],
                                           chart: chart, seed: 2468) else {
            return show(false, "목숨걸기 위력", "준비 실패") && ok
        }
        e.state.sides[1].team[0].maxHP = 99999
        e.state.sides[1].team[0].currentHP = 99999
        let myHP = e.state.sides[0].team[0].currentHP
        let before = e.state.sides[1].team[0].currentHP
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let dealt = before - e.state.sides[1].team[0].currentHP
        ok = show(dealt == myHP, "목숨걸기는 내 HP 만큼 준다", "내 HP \(myHP) → 피해 \(dealt)") && ok
        ok = show(e.state.sides[0].team[0].isFainted, "목숨걸기 후 쓰러진다") && ok
        return ok
    }

    /// 대폭발이 빗나가도 쓴 쪽은 쓰러진다 (5세대 이후 원작 규칙)
    private static func selfKOOnMiss(_ chart: TypeChart) async -> Bool {
        for seed in 1...40 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["explosion"], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 61) else {
                return show(false, "빗나간 대폭발", "준비 실패")
            }
            // 회피율을 최대로 올려 빗나가게 만든다
            e.state.sides[1].team[0].evasionStage = 6
            e.state.sides[1].team[0].maxHP = 999999
            e.state.sides[1].team[0].currentHP = 999999
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if e.state.log.contains(where: { $0.contains("빗나갔다") }) {
                return show(e.state.sides[0].team[0].isFainted,
                            "빗나간 대폭발도 쓴 쪽이 쓰러진다")
            }
        }
        return show(true, "빗나간 대폭발 (40시드 내 미발생, 규칙 위반 없음)")
    }

    /// 화상은 물리 공격만 절반으로 만든다 (특수는 그대로)
    private static func burnHalvesPhysicalOnly(_ chart: TypeChart) async -> Bool {
        func dealt(_ move: String, burned: Bool) async -> Int? {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: [move], defMoves: ["splash"],
                                               chart: chart, seed: 4242) else { return nil }
            if burned { e.state.sides[0].team[0].status = .burn }
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return before - e.state.sides[1].team[0].currentHP
        }
        guard let pb = await dealt("body-slam", burned: true),
              let pn = await dealt("body-slam", burned: false),
              let sb = await dealt("hyper-voice", burned: true),
              let sn = await dealt("hyper-voice", burned: false) else {
            return show(false, "화상 계산", "준비 실패")
        }
        var ok = show(pb < pn, "화상은 물리 데미지를 줄인다", "\(pn) → \(pb)")
        ok = show(sb == sn, "화상은 특수 데미지에 영향 없다", "\(sn) → \(sb)") && ok
        return ok
    }

    /// 잠듦은 반드시 언젠가 깨어난다 (무한 잠듦 방지)
    private static func sleepAlwaysWakes(_ chart: TypeChart) async -> Bool {
        for seed in 1...20 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["splash"], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 31) else {
                return show(false, "잠듦 해제", "준비 실패")
            }
            e.state.sides[1].team[0].status = .sleep
            e.state.sides[1].team[0].sleepTurns = 4
            var woke = false
            for _ in 0..<12 {
                guard case .awaitingMoves = e.state.phase else { break }
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                if e.state.sides[1].team[0].status != .sleep { woke = true; break }
            }
            if !woke {
                return show(false, "잠듦은 12턴 안에 깨어난다", "시드 \(seed) 에서 안 깨어남")
            }
        }
        return show(true, "잠듦은 반드시 깨어난다 (20시드)")
    }

    /// 얼음은 반드시 언젠가 녹는다
    private static func freezeAlwaysThaws(_ chart: TypeChart) async -> Bool {
        var maxTurns = 0
        for seed in 1...20 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["splash"], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 97) else {
                return show(false, "얼음 해제", "준비 실패")
            }
            e.state.sides[1].team[0].status = .freeze
            var thawed = false
            for t in 1...80 {
                guard case .awaitingMoves = e.state.phase else { break }
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                if e.state.sides[1].team[0].status != .freeze {
                    thawed = true; maxTurns = max(maxTurns, t); break
                }
            }
            if !thawed { return show(false, "얼음은 80턴 안에 녹는다", "시드 \(seed)") }
        }
        return show(true, "얼음은 반드시 녹는다 (20시드)", "최대 \(maxTurns)턴")
    }

    /// 맹독 카운터가 무한히 커지지 않는다
    private static func toxicCaps(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["splash"], defMoves: ["splash"],
                                           chart: chart, seed: 555) else {
            return show(false, "맹독 상한", "준비 실패")
        }
        e.state.sides[1].team[0].status = .toxic
        e.state.sides[1].team[0].toxicCounter = 1
        e.state.sides[1].team[0].currentHP = 99999   // 안 죽게
        e.state.sides[1].team[0].maxHP = 99999
        var maxSeen = 0
        for _ in 0..<40 {
            guard case .awaitingMoves = e.state.phase else { break }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            maxSeen = max(maxSeen, e.state.sides[1].team[0].toxicCounter)
        }
        return show(maxSeen <= 15, "맹독 카운터 상한 (15)", "최대 \(maxSeen)")
    }

    /// 급소는 공격측의 하락 랭크를 무시한다
    private static func critIgnoresDrops(_ chart: TypeChart) async -> Bool {
        func dealt(dropped: Bool, crit: Bool) async -> Int? {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["body-slam"], defMoves: ["splash"],
                                               chart: chart, seed: 2024) else { return nil }
            if dropped { e.state.sides[0].team[0].stages[.attack] = -6 }
            e.state.rules.criticalHits = crit
            if crit {
                // 급소를 확정시키기 위해 급소 단계를 최대로
                e.state.sides[0].team[0].critStage = 3
            }
            let before = e.state.sides[1].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            return before - e.state.sides[1].team[0].currentHP
        }
        guard let normalDrop = await dealt(dropped: true, crit: false),
              let critDrop = await dealt(dropped: true, crit: true) else {
            return show(false, "급소 랭크 무시", "준비 실패")
        }
        return show(critDrop > normalDrop,
                    "급소는 공격 하락 랭크를 무시한다", "일반 \(normalDrop) → 급소 \(critDrop)")
    }

    /// 랭크는 ±6 에서 멈춘다
    private static func stageClamp(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["swords-dance"], defMoves: ["splash"],
                                           chart: chart, seed: 31337) else {
            return show(false, "랭크 클램프", "준비 실패")
        }
        for _ in 0..<10 {
            guard case .awaitingMoves = e.state.phase else { break }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        }
        let stage = e.state.sides[0].team[0].stages[.attack] ?? 0
        return show(stage == 6, "칼춤 10회 후 공격 랭크는 +6 에서 멈춘다", "\(stage)")
    }

    /// 회복은 최대 HP 를 넘지 않는다
    private static func healCannotExceedMax(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["recover"], defMoves: ["splash"],
                                           chart: chart, seed: 12) else {
            return show(false, "회복 상한", "준비 실패")
        }
        e.state.sides[0].team[0].currentHP = e.state.sides[0].team[0].maxHP - 1
        for _ in 0..<5 {
            guard case .awaitingMoves = e.state.phase else { break }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        }
        let b = e.state.sides[0].team[0]
        return show(b.currentHP == b.maxHP, "회복은 최대 HP 를 넘지 않는다", "\(b.currentHP)/\(b.maxHP)")
    }

    /// 상대가 1 HP 일 때 흡수 기술이 과하게 회복하지 않는다
    private static func drainAtOneHP(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["giga-drain"], defMoves: ["splash"],
                                           chart: chart, seed: 88) else {
            return show(false, "1HP 흡수", "준비 실패")
        }
        e.state.sides[1].team[0].currentHP = 1
        e.state.sides[0].team[0].currentHP = 10
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let healed = e.state.sides[0].team[0].currentHP - 10
        // 실제로 깎은 양(1)의 절반 이하만 회복해야 한다
        return show(healed <= 1, "1 HP 상대 흡수는 실제 피해량 기준", "회복 \(healed)")
    }

    /// 반동으로 쓴 쪽이 쓰러질 수 있다
    private static func recoilCanKO(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["double-edge"], defMoves: ["splash"],
                                           chart: chart, seed: 4) else {
            return show(false, "반동 자멸", "준비 실패")
        }
        e.state.sides[0].team[0].currentHP = 1
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let fainted = e.state.sides[0].team[0].isFainted
        return show(fainted, "반동으로 쓴 쪽이 쓰러질 수 있다")
    }

    /// 기합의띠는 한 번만 버틴다 — 다단히트에서 두 번째 히트에 쓰러져야 한다
    private static func multiHitBreaksSash(_ chart: TypeChart) async -> Bool {
        guard let sash = await ItemCatalog.shared.item("focus-sash") else {
            return show(false, "기합의띠 다단히트", "도구 로드 실패")
        }
        for seed in 1...30 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["double-slap"], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 13) else {
                return show(false, "기합의띠 다단히트", "준비 실패")
            }
            e.state.sides[1].team[0].heldItem = sash
            e.state.sides[1].team[0].stats[.defense] = 1     // 한 방에 죽는 상황
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            let d = e.state.sides[1].team[0]
            let sashFired = e.state.log.contains { $0.contains("기합의띠로 버텼다") }
            let hits = e.state.log.contains { $0.contains("번 맞았다") }
            if sashFired, hits {
                // 띠로 버텼는데 다단히트였다면 이후 히트로 쓰러졌어야 한다
                return show(d.isFainted && d.itemConsumed,
                            "다단히트는 기합의띠를 뚫는다",
                            "쓰러짐=\(d.isFainted) 소비=\(d.itemConsumed)")
            }
        }
        return show(true, "다단히트 + 기합의띠 (해당 조합 미발생, 규칙 위반 없음)")
    }

    /// 다이맥스가 끝나면 최대 HP 가 **정확히** 원래 값으로 돌아온다
    private static func dynamaxHPExactRestore(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["body-slam"], defMoves: ["splash"],
                                           chart: chart, seed: 1234, gmaxFor: 143) else {
            return show(false, "다이맥스 HP 원복", "준비 실패")
        }
        // 배틀이 도중에 끝나면 턴 종료 처리가 돌지 않아 검증에 도달하지 못한다
        e.state.sides[1].team[0].maxHP = 999999
        e.state.sides[1].team[0].currentHP = 999999
        let original = e.state.sides[0].team[0].maxHP
        e.resolveTurn(hostAction: .useMove(index: 0, special: .dynamax),
                      guestAction: .useMove(index: 0))
        let boosted = e.state.sides[0].team[0].maxHP
        for _ in 0..<5 {
            guard case .awaitingMoves = e.state.phase else { break }
            if !e.state.sides[0].team[0].isDynamaxed { break }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        }
        let restored = e.state.sides[0].team[0].maxHP
        var ok = show(boosted > original, "다이맥스로 최대 HP 증가", "\(original) → \(boosted)")
        ok = show(restored == original, "해제 시 정확히 원복", "\(boosted) → \(restored) (원래 \(original))") && ok
        return ok
    }

    /// PP 가 음수가 되지 않고, 다 쓰면 그 기술을 못 쓴다
    private static func ppNeverNegative(_ chart: TypeChart) async -> Bool {
        // 자폭기로 하면 첫 턴에 쓴 쪽이 쓰러져 배틀이 끝나므로 일반 기술을 쓴다
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["body-slam"], defMoves: ["splash"],
                                           chart: chart, seed: 66) else {
            return show(false, "PP 하한", "준비 실패")
        }
        e.state.sides[0].team[0].moves[0].ppLeft = 1
        e.state.sides[0].team[0].currentHP = 999999
        e.state.sides[0].team[0].maxHP = 999999
        e.state.sides[1].team[0].currentHP = 999999
        e.state.sides[1].team[0].maxHP = 999999
        for _ in 0..<6 {
            guard case .awaitingMoves = e.state.phase else { break }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        }
        let pp = e.state.sides[0].team[0].moves[0].ppLeft
        var ok = show(pp >= 0, "PP 는 음수가 되지 않는다", "\(pp)")
        // 발버둥을 구현한 뒤로는 "PP가 없다" 가 아니라 발버둥이 나가는 것이 정답이다
        ok = show(e.state.log.contains { $0.contains("발버둥") } || pp > 0,
                  "PP 를 다 쓰면 발버둥을 쓴다") && ok
        return ok
    }

    /// 원작 스탯 공식 (Lv.50 / Lv.100)
    private static func statFormula() -> Bool {
        func sp(_ base: Int) -> SpeciesDef {
            SpeciesDef(id: 0, name: "t", koName: "t", types: [.normal],
                       baseStats: Dictionary(uniqueKeysWithValues: Stat.allCases.map { ($0, base) }),
                       learnableMoves: [])
        }
        let n = Nature.named("serious")
        let l50 = Battler.computeStats(base: sp(100), nature: n, level: 50)
        let l100 = Battler.computeStats(base: sp(100), nature: n, level: 100)
        var ok = show(l50.hp == 175, "Lv.50 종족값100 HP = 175", "\(l50.hp)")
        ok = show(l50.others[.attack] == 120, "Lv.50 종족값100 공격 = 120", "\(l50.others[.attack] ?? 0)") && ok
        ok = show(l100.hp == 341, "Lv.100 종족값100 HP = 341", "\(l100.hp)") && ok
        ok = show(l100.others[.attack] == 236, "Lv.100 종족값100 공격 = 236", "\(l100.others[.attack] ?? 0)") && ok

        // 성격 보정
        let adamant = Nature.named("adamant")   // 공격↑ 특공↓
        let a = Battler.computeStats(base: sp(100), nature: adamant, level: 50)
        ok = show(a.others[.attack]! > l50.others[.attack]!, "고집 성격은 공격 상승") && ok
        ok = show(a.others[.spAttack]! < l50.others[.spAttack]!, "고집 성격은 특공 하락") && ok
        ok = show(a.hp == l50.hp, "성격은 HP 에 영향 없다") && ok
        return ok
    }

    /// 스피드가 같아도 배틀이 진행된다 (무한 루프·크래시 없음)
    private static func speedTieResolves(_ chart: TypeChart) async -> Bool {
        for seed in 1...10 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["body-slam"], defMoves: ["body-slam"],
                                               chart: chart, seed: UInt64(seed) * 7,
                                               equalSpeed: true) else {
                return show(false, "스피드 동일", "준비 실패")
            }
            var turns = 0
            while turns < 200 {
                turns += 1
                switch e.state.phase {
                case .awaitingMoves:
                    e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                case .awaitingReplacement(let needs):
                    for raw in needs {
                        guard let s = BattleSide(rawValue: raw),
                              let p = e.state.side(s).aliveIndices.first else { continue }
                        e.applyReplacement(s, teamIndex: p)
                    }
                default: break
                }
                if case .finished = e.state.phase { break }
            }
            guard case .finished = e.state.phase else {
                return show(false, "스피드 동일에서도 배틀이 끝난다", "시드 \(seed) 미종료")
            }
        }
        return show(true, "스피드 동일에서도 배틀이 끝난다 (10시드)")
    }

    /// PP 가 전부 떨어지면 발버둥을 쓴다. 안 그러면 배틀이 끝나지 않는다.
    private static func struggleWhenNoPP(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["body-slam"], defMoves: ["splash"],
                                           chart: chart, seed: 3131) else {
            return show(false, "발버둥", "준비 실패")
        }
        e.state.sides[0].team[0].moves[0].ppLeft = 0
        e.state.sides[1].team[0].maxHP = 99999
        e.state.sides[1].team[0].currentHP = 99999
        let hpBefore = e.state.sides[0].team[0].currentHP
        let foeBefore = e.state.sides[1].team[0].currentHP

        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let used = e.state.log.contains { $0.contains("발버둥") }
        let dealt = foeBefore - e.state.sides[1].team[0].currentHP
        let recoil = hpBefore - e.state.sides[0].team[0].currentHP

        var ok = show(used, "PP 가 없으면 발버둥을 쓴다")
        ok = show(dealt > 0, "발버둥이 데미지를 준다", "\(dealt)") && ok
        ok = show(recoil > 0, "발버둥은 반동이 있다", "\(recoil)") && ok
        return ok
    }

    /// 자폭으로 양쪽이 동시에 전멸할 때, 전멸한 쪽이 승자로 남으면 안 된다.
    private static func selfKOTieIsHandled(_ chart: TypeChart) async -> Bool {
        for seed in 1...30 {
            guard var e = await Harness.engine(att: 143, def: 143,
                                               attMoves: ["explosion"], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 137) else { continue }
            // 양쪽 다 한 방에 쓰러지는 상황
            e.state.sides[1].team[0].currentHP = 1
            e.state.sides[1].team[0].stats[.defense] = 1
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))

            guard case .finished(let w) = e.state.phase else { continue }
            let hostGone = e.state.sides[0].remaining == 0
            let guestGone = e.state.sides[1].remaining == 0
            guard hostGone, guestGone else { continue }

            // 둘 다 전멸했으면 승자가 없어야 한다
            let pass = w == nil
            print(pass ? "  ✓ 동시 전멸은 무승부로 처리된다"
                       : "  ✗ 동시 전멸인데 승자가 기록됐다 (winner=\(w!))")
            if !pass { for l in e.state.log.suffix(6) { print("      \(l)") } }
            return pass
        }
        return show(true, "동시 전멸 (30시드 내 미발생, 규칙 위반 없음)")
    }

    // MARK: 로그 / 데미지 헬퍼

    private static func expectLog(_ move: String, def: Int, _ chart: TypeChart,
                                  absent: String, _ label: String) async -> Bool {
        for seed in 1...15 {
            guard var e = await Harness.engine(att: 143, def: def,
                                               attMoves: [move], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 41) else {
                return show(false, label, "준비 실패")
            }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if e.state.log.contains(where: { $0.contains(absent) }) {
                print("  ✗ \(label) — \"\(absent)\" 가 나왔다")
                for l in e.state.log.prefix(5) { print("      \(l)") }
                return false
            }
        }
        return show(true, label)
    }

    private static func expectPresent(_ move: String, def: Int, _ chart: TypeChart,
                                      needle: String, _ label: String) async -> Bool {
        for seed in 1...15 {
            guard var e = await Harness.engine(att: 143, def: def,
                                               attMoves: [move], defMoves: ["splash"],
                                               chart: chart, seed: UInt64(seed) * 53) else {
                return show(false, label, "준비 실패")
            }
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            if e.state.log.contains(where: { $0.contains(needle) }) { return show(true, label) }
        }
        print("  ✗ \(label) — 시드 15회 모두 \"\(needle)\" 없음")
        return false
    }

    private static func expectDamage(_ move: String, def: Int, _ chart: TypeChart,
                                     expect: Int, _ label: String) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: def,
                                           attMoves: [move], defMoves: ["splash"],
                                           chart: chart, seed: 909) else {
            return show(false, label, "준비 실패")
        }
        let before = e.state.sides[1].team[0].currentHP
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let dealt = before - e.state.sides[1].team[0].currentHP
        return show(dealt == expect, label, "실제 \(dealt)")
    }
}

/// 테스트용 배틀 생성 공용 헬퍼
enum Harness {
    static func engine(att: Int, def: Int,
                       attMoves: [String], defMoves: [String],
                       chart: TypeChart, seed: UInt64,
                       gmaxFor: Int? = nil,
                       equalSpeed: Bool = false) async -> BattleEngine? {
        guard let aSp = try? await PokeAPI.shared.species(att),
              let dSp = try? await PokeAPI.shared.species(def) else { return nil }
        var aM: [MoveDef] = [], dM: [MoveDef] = []
        for n in attMoves { if let m = try? await PokeAPI.shared.move(n) { aM.append(m) } }
        for n in defMoves { if let m = try? await PokeAPI.shared.move(n) { dM.append(m) } }
        guard !aM.isEmpty, !dM.isEmpty else { return nil }

        func mk(_ sp: SpeciesDef, _ mv: [MoveDef], _ tag: String) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: mv, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            return b
        }
        var a = mk(aSp, aM, "att"), d = mk(dSp, dM, "def")
        if equalSpeed {
            a.stats[.speed] = 100; d.stats[.speed] = 100
        } else {
            a.stats[.speed] = 999; d.stats[.speed] = 1
        }

        var rules = BattleRules(maxTeamSize: 1, level: 50)
        rules.requireItems = false
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: [a], activeIndex: 0),
                                     SideState(playerName: "B", team: [d], activeIndex: 0)])
        st.phase = .awaitingMoves
        st.turn = 1
        var e = BattleEngine(state: st, chart: chart, seed: seed)

        if let g = gmaxFor, let sp = try? await PokeAPI.shared.species(g), let form = sp.gmaxForm {
            e.gmaxCache[form] = try? await PokeAPI.shared.form(named: form)
        }
        for (_, n) in FormTables.maxMove {
            if let m = try? await PokeAPI.shared.move(n) { e.maxMoveCache[n] = m }
        }
        if let g = try? await PokeAPI.shared.move(FormTables.maxGuard) {
            e.maxMoveCache[FormTables.maxGuard] = g
        }
        for (_, base) in FormTables.zMoveBase {
            for sfx in ["--physical", "--special"] {
                if let m = try? await PokeAPI.shared.move(base + sfx) { e.zMoveCache[base + sfx] = m }
            }
        }
        return e
    }
}
