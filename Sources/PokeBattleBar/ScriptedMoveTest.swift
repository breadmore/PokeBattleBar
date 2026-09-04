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

        // MARK: 모으는 기술 · 반동 기술을 **하나씩 전부** 확인한다
        //
        // 솔라빔 하나만 보고 넘어가면 땅파기·공중날기처럼 숨는 기술이
        // 제대로 되는지 알 수 없다. 데이터에 charge/recharge 로 표시된 기술을
        // 전부 돌려본다.
        print("\n-- 모으는 기술 전체 --")
        let chargeNames = ["solar-beam", "solar-blade", "fly", "bounce", "dig", "dive",
                           "sky-attack", "phantom-force", "shadow-force", "razor-wind",
                           "skull-bash", "freeze-shock", "ice-burn", "geomancy",
                           "meteor-beam", "electro-shot"]
        var chargeChecked = 0
        for name in chargeNames {
            guard let mv = try? await PokeAPI.shared.move(name) else { continue }
            guard mv.isCharge else {
                // 데이터가 charge 로 표시하지 않은 기술은 2턴이 아니다 — 건너뛴다
                continue
            }
            chargeChecked += 1
            guard let r = await probe(move: name, user: 143, foe: 143, chart: chart) else {
                ok = show(false, "\(mv.display) 실행") && ok; continue
            }
            let charging = r.user.isCharging
            let noDamage = r.foe.currentHP == r.foe.maxHP
            let hides = mv.chargeHides
            let hidden = r.user.chargeHidden
            var note = charging ? "모으는 중" : "모으지 않음"
            if hides { note += hidden ? " · 숨음" : " · 숨지 않음(문제)" }
            ok = show(charging && noDamage && (hides == hidden),
                      "\(mv.display) — 첫 턴에 모으고 데미지 없음"
                      + (hides ? " · 숨는다" : ""), note) && ok

            // 두 번째 턴에 실제로 나가는가
            if let r2 = await twoTurn(first: name, then: name,
                                     user: 143, foe: 143, chart: chart) {
                ok = show(!r2.user.isCharging && !r2.user.chargeHidden,
                          "\(mv.display) — 두 번째 턴에 나가고 숨김이 풀린다") && ok
            }
        }
        ok = show(chargeChecked >= 8, "모으는 기술을 여러 개 확인했다",
                  "\(chargeChecked)개") && ok

        print("\n-- 숨는 동안 공격이 빗나가는가 --")
        // 땅파기·공중날기의 핵심은 그 턴에 안 맞는 것이다
        if let r = await hiddenDodge(chart: chart) {
            ok = show(r.dodged, "숨은 동안 상대 공격이 빗나간다",
                      r.detail) && ok
        } else {
            ok = show(false, "숨기 회피 검사") && ok
        }

        print("\n-- 반동 기술 전체 --")
        let rechargeNames = ["hyper-beam", "giga-impact", "blast-burn", "hydro-cannon",
                             "frenzy-plant", "rock-wrecker", "roar-of-time",
                             "prismatic-laser", "eternabeam", "meteor-assault"]
        var rechargeChecked = 0
        for name in rechargeNames {
            guard let mv = try? await PokeAPI.shared.move(name), mv.mustRecharge else { continue }
            rechargeChecked += 1
            guard let r = await probe(move: name, user: 143, foe: 143, chart: chart) else {
                ok = show(false, "\(mv.display) 실행") && ok; continue
            }
            ok = show(r.user.mustRechargeTurns == 1,
                      "\(mv.display) — 다음 턴 반동이 예약된다",
                      "\(r.user.mustRechargeTurns)") && ok
        }
        ok = show(rechargeChecked >= 4, "반동 기술을 여러 개 확인했다",
                  "\(rechargeChecked)개") && ok

        // MARK: 승부가 나는 시점
        //
        // 원작 규칙: 쓰러진 포켓몬은 행동하지 않고, 한쪽이 전멸하면 **그 자리에서**
        // 배틀이 끝난다 — 턴 종료 지속 데미지(독·화상)도 돌지 않는다.
        // 이게 어긋나면 이겨야 할 배틀이 무승부가 된다.
        print("\n-- 쓰러뜨린 뒤 승부 --")
        if let r = await knockoutTiming(poisonedWinner: false, chart: chart) {
            ok = show(r.finished, "마지막 상대를 쓰러뜨리면 그 자리에서 끝난다", r.detail) && ok
            ok = show(r.winnerIsMe, "내가 이긴 것으로 기록된다", r.detail) && ok
            ok = show(!r.foeActed, "쓰러진 상대는 반격하지 않는다",
                      r.foeActed ? "반격 로그가 있다" : "반격 없음") && ok
        } else { ok = show(false, "쓰러뜨리기 검사") && ok }

        print("\n-- 독에 걸린 채로 이겼을 때 --")
        // 이겼는데 턴 종료 독 데미지로 내가 죽어 무승부가 되면 안 된다
        if let r = await knockoutTiming(poisonedWinner: true, chart: chart) {
            ok = show(r.winnerIsMe, "독에 걸려 있어도 이긴 것으로 기록된다", r.detail) && ok
            ok = show(!r.drew, "무승부가 되지 않는다", r.detail) && ok
            ok = show(r.myHPAfter > 0, "이긴 뒤에 독으로 죽지 않는다",
                      "내 HP \(r.myHPAfter)") && ok
        } else { ok = show(false, "독 상태 승리 검사") && ok }

        // MARK: 원시회귀 — 구슬을 지니면 등장할 때 자동으로 바뀐다
        print("\n-- 원시회귀 --")
        if let r = await primalCheck(speciesID: 383, orb: "red-orb",
                                     form: "groudon-primal", chart: chart) {
            ok = show(r.became, "그란돈이 구슬을 지니면 원시회귀한다", r.detail) && ok
            ok = show(r.stronger, "종족값이 올라간다", r.detail2) && ok
            ok = show(r.sawLog, "로그에 남는다") && ok
        } else { ok = show(false, "그란돈 원시회귀 검사") && ok }

        if let r = await primalCheck(speciesID: 382, orb: "blue-orb",
                                     form: "kyogre-primal", chart: chart) {
            ok = show(r.became, "가이오가도 원시회귀한다", r.detail) && ok
        }

        // 구슬이 없으면 바뀌지 않아야 한다
        if let r = await primalCheck(speciesID: 383, orb: nil,
                                     form: "groudon-primal", chart: chart) {
            ok = show(!r.became, "구슬이 없으면 바뀌지 않는다", r.detail) && ok
        }
        // 엉뚱한 종이 구슬을 들어도 바뀌지 않아야 한다
        if let r = await primalCheck(speciesID: 143, orb: "red-orb",
                                     form: "groudon-primal", chart: chart) {
            ok = show(!r.became, "다른 종은 구슬로 바뀌지 않는다", r.detail) && ok
        }

        // MARK: 화면 (리플렉터 · 빛의장막 · 오로라베일)
        //
        // 라벨만 뜨고 데미지가 그대로면 아무 의미가 없다 —
        // **실제로 절반이 되는지**를 본다.
        print("\n-- 리플렉터 (물리 절반) --")
        if let r = await screenCheck(screen: "reflect", attack: "tackle",
                                     weather: nil, chart: chart) {
            ok = show(r.applied, "화면이 세워진다", r.detail) && ok
            ok = show(r.halved, "물리 데미지가 절반이 된다", r.detail2) && ok
        } else { ok = show(false, "리플렉터 검사") && ok }

        print("\n-- 리플렉터는 특수를 막지 않는다 --")
        if let r = await screenCheck(screen: "reflect", attack: "swift",
                                     weather: nil, chart: chart) {
            ok = show(!r.halved, "특수 데미지는 그대로", r.detail2) && ok
        }

        print("\n-- 빛의장막 (특수 절반) --")
        if let r = await screenCheck(screen: "light-screen", attack: "swift",
                                     weather: nil, chart: chart) {
            ok = show(r.halved, "특수 데미지가 절반이 된다", r.detail2) && ok
        }
        if let r = await screenCheck(screen: "light-screen", attack: "tackle",
                                     weather: nil, chart: chart) {
            ok = show(!r.halved, "물리 데미지는 그대로", r.detail2) && ok
        }

        print("\n-- 오로라베일 --")
        // 눈이 안 오면 실패해야 한다 (그래서 아무 효과가 없어 보이기 쉽다)
        if let r = await screenCheck(screen: "aurora-veil", attack: "tackle",
                                     weather: nil, chart: chart) {
            ok = show(!r.applied, "눈이 없으면 실패한다", r.detail) && ok
            ok = show(!r.halved, "실패하면 데미지도 그대로", r.detail2) && ok
        }
        // 눈이 오면 걸리고 물리·특수 둘 다 절반
        if let r = await screenCheck(screen: "aurora-veil", attack: "tackle",
                                     weather: "snowscape", chart: chart) {
            ok = show(r.applied, "눈이 오면 걸린다", r.detail) && ok
            ok = show(r.halved, "물리 데미지가 절반", r.detail2) && ok
        } else { ok = show(false, "오로라베일(눈) 검사") && ok }
        if let r = await screenCheck(screen: "aurora-veil", attack: "swift",
                                     weather: "snowscape", chart: chart) {
            ok = show(r.halved, "특수 데미지도 절반", r.detail2) && ok
        }

        print("\n-- 깨뜨리다로 화면을 부순다 --")
        if let r = await breakScreen(chart: chart) {
            ok = show(r.broken, "깨뜨리다가 상대 화면을 부순다", r.detail) && ok
        } else { ok = show(false, "화면 파괴 검사") && ok }

        // MARK: 앙코르 · 하품 · 비축 · 누적 위력 · 전자부유 · 검은눈빛
        print("\n-- 앙코르 --")
        // 상대가 기술을 쓴 뒤여야 걸린다 — 두 턴을 돌린다
        if let r = await twoTurn(first: "encore", then: "encore",
                                user: 94, foe: 143, chart: chart) {
            // 첫 턴엔 상대의 마지막 기술이 없어 실패, 둘째 턴엔 걸린다
            ok = show(r.foe.isEncored || r.log.contains { $0.contains("앙코르") },
                      "앙코르가 상대에게 걸린다",
                      r.log.first { $0.contains("앙코르") } ?? "로그 없음") && ok
        }
        if let r = await encoreForces(chart: chart) {
            ok = show(r.forced, "앙코르에 걸리면 그 기술만 나간다", r.detail) && ok
        } else { ok = show(false, "앙코르 강제 검사") && ok }

        print("\n-- 하품 --")
        if let r = await probe(move: "yawn", user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.drowsyTurns > 0, "졸음이 걸린다", "\(r.foe.drowsyTurns)턴") && ok
            ok = show(r.foe.status == .none, "그 턴에는 아직 안 잠든다") && ok
        }
        if let r = await twoTurn(first: "yawn", then: "yawn",
                                user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.status == .sleep, "다음 턴이 끝나면 잠든다",
                      "\(r.foe.status)") && ok
        }

        print("\n-- 비축 · 통째로꿀꺽 · 뱉어내기 --")
        if let r = await probe(move: "stockpile", user: 143, foe: 143, chart: chart) {
            ok = show(r.user.stockpile == 1, "비축이 쌓인다", "\(r.user.stockpile)") && ok
            ok = show((r.user.stages[.defense] ?? 0) == 1, "방어가 오른다") && ok
        }
        if let r = await twoTurn(first: "stockpile", then: "swallow",
                                user: 143, foe: 143, chart: chart,
                                setup: { b in b.currentHP = b.maxHP / 3 }) {
            ok = show(r.user.stockpile == 0, "삼키면 비축이 비워진다") && ok
            ok = show(r.user.currentHP > r.user.maxHP / 3, "삼키면 회복된다",
                      "\(r.user.currentHP)/\(r.user.maxHP)") && ok
        }
        // 비축 없이 뱉어내기는 실패해야 한다
        if let r = await probe(move: "spit-up", user: 143, foe: 143, chart: chart) {
            ok = show(r.foe.currentHP == r.foe.maxHP,
                      "비축 없이 뱉어내기는 실패한다", "\(r.foe.currentHP)/\(r.foe.maxHP)") && ok
        }

        print("\n-- 연속으로 쓰면 세지는 기술 --")
        if let r = await escalating(chart: chart) {
            ok = show(r.grew, "연속자르기는 쓸수록 세진다", r.detail) && ok
        } else { ok = show(false, "누적 위력 검사") && ok }

        print("\n-- 전자부유 --")
        if let r = await probe(move: "magnet-rise", user: 143, foe: 143, chart: chart) {
            ok = show(r.user.magnetRiseTurns == 5, "쓴 턴이 지나면 5턴 남는다",
                      "\(r.user.magnetRiseTurns)") && ok
        }

        print("\n-- 검은눈빛 --")
        if let r = await probe(move: "mean-look", user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.cannotFlee, "상대가 도망갈 수 없게 된다") && ok
        }

        // MARK: 구애 도구가 턴을 날리지 않는가
        //
        // 예전에는 고정된 기술이 아닌 것을 고르면 안내만 하고 턴이 그냥
        // 지나갔다. 원작은 애초에 고를 수 없게 막으므로 턴이 날아가지 않는다.
        print("\n-- 구애 도구 --")
        if let r = await choiceLock(chart: chart) {
            ok = show(r.lockedAfterFirst, "첫 기술을 쓰면 그 기술로 고정된다",
                      r.detail) && ok
            ok = show(r.secondTurnDealtDamage,
                      "다른 기술을 골라도 턴이 날아가지 않는다 (고정된 기술이 나간다)",
                      r.detail2) && ok
        } else {
            ok = show(false, "구애 도구 검사") && ok
        }

        // MARK: 스피드가 같을 때 선공이 매 턴 무작위인가
        //
        // 한쪽이 계속 먼저 가면 동타에서 불공평하다.
        // 씨드마다 다른 것으로는 부족하다 — **한 배틀 안에서 턴마다** 갈려야 한다.
        print("\n-- 스피드 동타 --")
        if let r = await tieOrder(chart: chart) {
            let hostFirst = r.hostFirst, total = r.total
            print("  \(total)턴 중 내가 선공한 횟수: \(hostFirst)")
            ok = show(total >= 40, "표본이 충분하다", "\(total)턴") && ok
            ok = show(hostFirst > 0 && hostFirst < total,
                      "한쪽이 계속 먼저 가지 않는다", "\(hostFirst)/\(total)") && ok
            // 치우침이 심하면 무작위가 아니다 (이항분포로 40턴이면 25~75% 안에 든다)
            let ratio = Double(hostFirst) / Double(total)
            ok = show(ratio > 0.25 && ratio < 0.75, "치우치지 않는다",
                      String(format: "%.0f%%", ratio * 100)) && ok
        } else {
            ok = show(false, "스피드 동타 표본 수집") && ok
        }

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    /// 구애머리띠를 끼고 첫 턴에 A 를 쓴 뒤, 둘째 턴에 B 를 고른다.
    /// 턴이 날아가지 않고 A 가 나가야 한다.
    private static func choiceLock(chart: TypeChart) async -> (
        lockedAfterFirst: Bool, detail: String,
        secondTurnDealtDamage: Bool, detail2: String
    )? {
        await ItemCatalog.shared.loadAll()      // 이걸 빠뜨리면 도구를 못 찾는다
        guard let sp = try? await PokeAPI.shared.species(143),
              let tackle = try? await PokeAPI.shared.move("tackle"),
              let headbutt = try? await PokeAPI.shared.move("headbutt"),
              let band = await ItemCatalog.shared.item("choice-band"),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }

        func make(_ ms: [MoveDef], _ tag: String, item: ItemDef?, speed: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50, heldItem: item)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            b.maxHP = 9999; b.currentHP = 9999
            return b
        }

        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make([tackle, headbutt], "h",
                                                           item: band, speed: 999)],
                                               activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make([splash], "g", item: nil, speed: 1)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 55)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        // 첫 턴: 0번(몸통박치기)
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let locked = e.state.sides[0].team[0].lockedMoveIndex
        let d1 = "고정 인덱스 \(locked.map(String.init) ?? "없음")"

        // 둘째 턴: 일부러 1번(들이받기)을 고른다 → 턴이 날아가면 안 된다
        let before = e.state.sides[1].team[0].currentHP
        let logBefore = e.state.log.count
        e.resolveTurn(hostAction: .useMove(index: 1), guestAction: .useMove(index: 0))
        let after = e.state.sides[1].team[0].currentHP
        let lines = Array(e.state.log[logBefore...])
        let usedLocked = lines.contains { $0.contains("몸통박치기") }
        let d2 = "상대 HP \(before) → \(after)"
            + (usedLocked ? " · 고정된 기술이 나갔다" : " · 고정된 기술이 안 나갔다")

        return (locked == 0, d1, after < before && usedLocked, d2)
    }

    /// 땅속에 숨은 동안 상대 공격이 빗나가는지 본다.
    /// 내가 땅파기로 숨고, 상대가 (더 느리게) 공격한다.
    private static func hiddenDodge(chart: TypeChart) async -> (dodged: Bool, detail: String)? {
        guard let sp = try? await PokeAPI.shared.species(143),
              let dig = try? await PokeAPI.shared.move("dig"),
              let tackle = try? await PokeAPI.shared.move("tackle") else { return nil }

        func make(_ ms: [MoveDef], _ tag: String, speed: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            return b
        }
        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make([dig], "h", speed: 999)], activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make([tackle], "g", speed: 1)], activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 31)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        let hpBefore = e.state.sides[0].team[0].currentHP
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let hpAfter = e.state.sides[0].team[0].currentHP
        let missed = e.state.log.contains { $0.contains("맞지 않았다") || $0.contains("피했다") }
        return (hpAfter == hpBefore,
                "HP \(hpBefore) → \(hpAfter)" + (missed ? " · 빗맞음 로그 있음" : ""))
    }

    /// 스피드가 완전히 같은 두 마리로 여러 턴을 돌려 선공 분포를 센다
    private static func tieOrder(chart: TypeChart) async -> (hostFirst: Int, total: Int)? {
        // **서로 다른 종**이어야 로그에서 누가 먼저 움직였는지 알 수 있다.
        // 같은 종으로 하면 두 줄이 똑같아서 구분이 안 된다 (그렇게 짰다가 100% 가 나왔다).
        guard let mine = try? await PokeAPI.shared.species(143),      // 잠만보
              let theirs = try? await PokeAPI.shared.species(94),     // 팬텀
              let tackle = try? await PokeAPI.shared.move("tackle") else { return nil }

        var hostFirst = 0, total = 0
        for seed in 1...12 {
            func make(_ sp: SpeciesDef, _ tag: String) -> Battler {
                let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                      rarity: "common", isShiny: false, origin: .dex,
                                      fullyEvolved: true)
                var b = Battler.make(slot: slot, species: sp, moves: [tackle], level: 50)
                b.moves[0].ppLeft = 99
                b.stats[.speed] = 100          // 스피드만 완전히 같게
                b.maxHP = 9999; b.currentHP = 9999   // 오래 버티게
                return b
            }
            var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                                 sides: [SideState(playerName: "나", team: [make(mine, "h")], activeIndex: 0),
                                         SideState(playerName: "상대", team: [make(theirs, "g")], activeIndex: 0)])
            st.phase = .chooseLead
            var e = BattleEngine(state: st, chart: chart, seed: UInt64(seed) * 7919)
            e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
            e.beginBattle()

            for _ in 0..<5 {
                guard case .awaitingMoves = e.state.phase else { break }
                let before = e.state.log.count
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                // 이번 턴 로그에서 **누가 먼저 나왔는지** 본다
                let lines = Array(e.state.log[before...])
                guard let first = lines.first(where: { $0.contains("의 몸통박치기") }) else { continue }
                total += 1
                if first.hasPrefix(mine.display) { hostFirst += 1 }
            }
        }
        return total > 0 ? (hostFirst, total) : nil
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
                                user: Int, foe: Int, chart: TypeChart,
                                setup: ((inout Battler) -> Void)? = nil) async -> Probe? {
        await battle(moves: [first, second], user: user, foe: foe, chart: chart, setup: setup)
    }

    /// 마지막 상대를 쓰러뜨렸을 때 승부가 어떻게 나는지 본다.
    ///
    /// - Parameter poisonedWinner: 이기는 쪽이 독에 걸린 상태인가.
    ///   턴 종료 독 데미지가 승리 뒤에 돌면 무승부가 되어버린다.
    private static func knockoutTiming(poisonedWinner: Bool, chart: TypeChart) async -> (
        finished: Bool, winnerIsMe: Bool, drew: Bool, foeActed: Bool,
        myHPAfter: Int, detail: String
    )? {
        guard let sp = try? await PokeAPI.shared.species(143),
              let tackle = try? await PokeAPI.shared.move("tackle") else { return nil }

        func make(_ tag: String, speed: Int, hp: Int, poisoned: Bool) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: [tackle], level: 50)
            b.moves[0].ppLeft = 99
            b.stats[.speed] = speed
            b.maxHP = hp
            b.currentHP = hp
            if poisoned { b.status = .poison }
            return b
        }

        // 나: 빠르고 한 방에 죽일 수 있다. 독에 걸렸다면 HP 를 아슬아슬하게 둔다.
        //     (독 데미지는 최대 HP 의 1/8 이므로 8 이면 죽는다)
        let myHP = poisonedWinner ? 8 : 300
        let me = make("h", speed: 999, hp: myHP, poisoned: poisonedWinner)
        // 상대: 느리고 한 방에 죽는다
        let foe = make("g", speed: 1, hp: 1, poisoned: false)

        var rules = BattleRules(maxTeamSize: 1, level: 50)
        rules.statusEffects = true
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "나", team: [me], activeIndex: 0),
                                     SideState(playerName: "상대", team: [foe], activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 5)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        let logBefore = e.state.log.count
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let lines = Array(e.state.log[logBefore...])

        var finished = false, winner: Int??  = nil
        if case .finished(let w) = e.state.phase { finished = true; winner = w }

        // 상대가 행동했는가 — 쓰러진 뒤 반격하면 로그에 두 번째 몸통박치기가 남는다
        let attackLines = lines.filter { $0.contains("몸통박치기") }
        let foeActed = attackLines.count > 1

        let w = winner ?? nil
        let hpLeft = e.state.sides[0].team[0].currentHP
        return (finished,
                w == BattleSide.host.rawValue,
                finished && w == nil,
                foeActed,
                hpLeft,
                "종료=\(finished) 승자=\(w.map(String.init) ?? "무승부") 내HP=\(hpLeft)"
                + " 공격로그=\(attackLines.count)")
    }

    /// 원시회귀가 등장할 때 발동하는지 본다
    private static func primalCheck(speciesID: Int, orb: String?, form: String,
                                    chart: TypeChart) async -> (
        became: Bool, detail: String, stronger: Bool, detail2: String, sawLog: Bool
    )? {
        await ItemCatalog.shared.loadAll()
        guard let sp = try? await PokeAPI.shared.species(speciesID),
              let tackle = try? await PokeAPI.shared.move("tackle"),
              let splash = try? await PokeAPI.shared.move("splash"),
              let foeSp = try? await PokeAPI.shared.species(143) else { return nil }
        var orbItem: ItemDef?
        if let orb { orbItem = await ItemCatalog.shared.item(orb) }
        if orb != nil, orbItem == nil { return nil }

        func make(_ species: SpeciesDef, _ ms: [MoveDef], _ tag: String,
                  item: ItemDef?) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: species.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: species, moves: ms, level: 50,
                                 heldItem: item)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            return b
        }

        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make(sp, [tackle], "h", item: orbItem)],
                                               activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make(foeSp, [splash], "g", item: nil)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 7)
        // 원시 폼 스탯을 엔진에 심어야 한다 (앱은 preloadForms 가 한다)
        if let fs = try? await PokeAPI.shared.form(named: form) {
            e.megaCache[form] = fs
        }
        let before = e.state.sides[0].team[0]
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()
        let after = e.state.sides[0].team[0]

        let sumBefore = Stat.allCases.reduce(0) { $0 + (before.stats[$1] ?? 0) }
        let sumAfter = Stat.allCases.reduce(0) { $0 + (after.stats[$1] ?? 0) }
        let sawLog = e.state.log.contains { $0.contains("원시의 것으로") }
        return (after.isPrimal,
                "원시=\(after.isPrimal) 폼=\(after.spriteForm ?? "기본")",
                sumAfter > sumBefore,
                "실능력치 합 \(sumBefore) → \(sumAfter)",
                sawLog)
    }

    /// 화면을 세운 뒤 데미지가 정말 절반이 되는지 본다.
    ///
    /// 같은 씨드로 두 번 돌린다 — 한 번은 화면 없이, 한 번은 화면을 세우고.
    /// 난수가 같으므로 차이는 화면 때문이다.
    private static func screenCheck(screen: String, attack: String, weather: String?,
                                    chart: TypeChart) async -> (
        applied: Bool, detail: String, halved: Bool, detail2: String
    )? {
        guard let sp = try? await PokeAPI.shared.species(143),
              let scr = try? await PokeAPI.shared.move(screen),
              let atk = try? await PokeAPI.shared.move(attack),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }
        var weatherMove: MoveDef?
        if let w = weather { weatherMove = try? await PokeAPI.shared.move(w) }

        /// 방어측이 `defenderMoves` 를 쓰고, 공격측이 `attack` 으로 때린다.
        /// 돌려주는 값은 공격이 준 데미지.
        func run(defenderMoves: [MoveDef]) -> (dmg: Int, log: [String], screenOn: Bool) {
            func make(_ ms: [MoveDef], _ tag: String, speed: Int) -> Battler {
                let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                      rarity: "common", isShiny: false, origin: .dex,
                                      fullyEvolved: true)
                var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
                for i in b.moves.indices { b.moves[i].ppLeft = 99 }
                b.stats[.speed] = speed
                b.maxHP = 99999; b.currentHP = 99999
                return b
            }
            var rules = BattleRules(maxTeamSize: 1, level: 50)
            rules.weather = true
            // 방어측(host)이 화면을 세우고, 공격측(guest)이 때린다
            var st = BattleState(rules: rules,
                                 sides: [SideState(playerName: "방어",
                                                   team: [make(defenderMoves, "d", speed: 999)],
                                                   activeIndex: 0),
                                         SideState(playerName: "공격",
                                                   team: [make([atk], "a", speed: 1)],
                                                   activeIndex: 0)])
            st.phase = .chooseLead
            var e = BattleEngine(state: st, chart: chart, seed: 4242)
            e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
            e.beginBattle()

            // 날씨를 먼저 깔아야 하는 경우 한 턴 더 쓴다
            var idx = 0
            if weatherMove != nil, defenderMoves.count > 1 {
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                idx = 1
            }
            // 방어측이 화면(또는 아무것도)을 쓴다
            e.resolveTurn(hostAction: .useMove(index: idx), guestAction: .useMove(index: 0))
            let on = e.state.sides[0].hasAnyScreen
            // 다음 턴의 데미지를 잰다
            let before = e.state.sides[0].team[0].currentHP
            e.resolveTurn(hostAction: .useMove(index: idx), guestAction: .useMove(index: 0))
            return (before - e.state.sides[0].team[0].currentHP, e.state.log, on)
        }

        // 기준: 화면 없이 (튀어오르기만 쓴다)
        var baseMoves: [MoveDef] = [splash]
        var screenMoves: [MoveDef] = [scr]
        if let wm = weatherMove {
            baseMoves = [wm, splash]
            screenMoves = [wm, scr]
        }
        let base = run(defenderMoves: baseMoves)
        let withScreen = run(defenderMoves: screenMoves)

        let ratio = base.dmg > 0 ? Double(withScreen.dmg) / Double(base.dmg) : 1
        return (withScreen.screenOn,
                "화면 걸림=\(withScreen.screenOn)",
                ratio < 0.65,
                String(format: "데미지 %d → %d (%.0f%%)", base.dmg, withScreen.dmg, ratio * 100))
    }

    /// 깨뜨리다가 상대 화면을 부수는지 본다
    private static func breakScreen(chart: TypeChart) async -> (broken: Bool, detail: String)? {
        guard let sp = try? await PokeAPI.shared.species(143),
              let reflect = try? await PokeAPI.shared.move("reflect"),
              let brick = try? await PokeAPI.shared.move("brick-break") else { return nil }

        func make(_ ms: [MoveDef], _ tag: String, speed: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            b.maxHP = 99999; b.currentHP = 99999
            return b
        }
        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "방어",
                                               team: [make([reflect], "d", speed: 999)],
                                               activeIndex: 0),
                                     SideState(playerName: "공격",
                                               team: [make([brick], "a", speed: 1)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 909)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let onBefore = e.state.sides[0].hasAnyScreen
        let onAfter = e.state.sides[0].hasAnyScreen
        let sawBreak = e.state.log.contains { $0.contains("화면을 부쉈다") }
        return (onBefore && !onAfter || sawBreak,
                "세워짐=\(onBefore) · 부숨 로그=\(sawBreak)")
    }

    /// 앙코르에 걸린 쪽이 정말 그 기술만 쓰는지 본다
    private static func encoreForces(chart: TypeChart) async -> (forced: Bool, detail: String)? {
        guard let sp = try? await PokeAPI.shared.species(143),
              let tackle = try? await PokeAPI.shared.move("tackle"),
              let headbutt = try? await PokeAPI.shared.move("headbutt"),
              let encore = try? await PokeAPI.shared.move("encore") else { return nil }

        func make(_ ms: [MoveDef], _ tag: String, speed: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            b.maxHP = 9999; b.currentHP = 9999
            return b
        }
        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make([encore], "h", speed: 999)],
                                               activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make([tackle, headbutt], "g", speed: 1)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 77)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        // 1턴: 상대가 0번(몸통박치기)을 쓴다
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        // 2턴: 내가 앙코르 -> 상대는 0번에 묶인다
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let encored = e.state.sides[1].team[0].isEncored
        // 3턴: 상대가 1번(들이받기)을 골라도 0번이 나가야 한다
        let logBefore = e.state.log.count
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 1))
        let lines = Array(e.state.log[logBefore...])
        let usedLocked = lines.contains { $0.contains("몸통박치기") }
        let sawNote = lines.contains { $0.contains("앙코르 때문에") }
        return (encored && usedLocked,
                "앙코르 걸림=\(encored) · 고정 기술 사용=\(usedLocked)"
                + (sawNote ? " · 안내 있음" : ""))
    }

    /// 연속자르기를 세 번 써서 위력이 커지는지 본다
    private static func escalating(chart: TypeChart) async -> (grew: Bool, detail: String)? {
        guard let sp = try? await PokeAPI.shared.species(143),
              let fury = try? await PokeAPI.shared.move("fury-cutter"),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }

        func make(_ ms: [MoveDef], _ tag: String, speed: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            b.maxHP = 99999; b.currentHP = 99999
            return b
        }
        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make([fury], "h", speed: 999)],
                                               activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make([splash], "g", speed: 1)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 101)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        // 연속자르기는 95% 명중이라 빗맞을 수 있고 데미지에 난수도 있다.
        // 여러 씨드를 돌려 **턴마다 최대 데미지**를 모으면 위력 증가만 남는다.
        var best = [0, 0, 0, 0]
        for seed in 1...10 {
            var e2 = BattleEngine(state: st, chart: chart, seed: UInt64(seed) * 613)
            e2.setLead(.host, index: 0); e2.setLead(.guest, index: 0)
            e2.beginBattle()
            for t in 0..<4 {
                guard case .awaitingMoves = e2.state.phase else { break }
                let before = e2.state.sides[1].team[0].currentHP
                e2.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                best[t] = max(best[t], before - e2.state.sides[1].team[0].currentHP)
            }
        }
        _ = e
        let detail = "턴별 최대 데미지 " + best.map(String.init).joined(separator: " → ")
        // 위력이 40 → 80 → 160 → 320 이면 데미지도 대략 그렇게 커진다
        return (best[1] > best[0] * 3 / 2 && best[3] > best[0] * 4, detail)
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
