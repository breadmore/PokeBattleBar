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
            // **에스퍼(뮤)를 대상으로 쓴다.** 에스퍼는 어떤 타입에도 무효가 없다 —
            // 잠만보(노말)를 쓰면 고스트 기술이 0 데미지라 구현 문제로 오해하게 된다.
            guard let r = await probe(move: name, user: 143, foe: 151, chart: chart) else {
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

            // 두 번째 턴에 실제로 **데미지가 들어가는지**까지 본다.
            // 예전에는 isCharging 이 풀리는 것만 봤다 — 그러면 발사가 안 돼도 통과한다.
            if let r2 = await twoTurn(first: name, then: name,
                                     user: 143, foe: 151, chart: chart) {
                ok = show(!r2.user.isCharging && !r2.user.chargeHidden,
                          "\(mv.display) — 두 번째 턴에 숨김이 풀린다") && ok
                if (mv.power ?? 0) > 0 {
                    ok = show(r2.foe.currentHP < r2.foe.maxHP,
                              "\(mv.display) — 두 번째 턴에 데미지가 들어간다",
                              "\(r2.foe.currentHP)/\(r2.foe.maxHP)") && ok
                }
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

        // MARK: 떨어뜨리기 · 트집 · 사슬묶기
        print("\n-- 떨어뜨리기 --")
        if let r = await smackDownCheck(chart: chart) {
            ok = show(r.grounded, "상대를 땅으로 끌어내린다", r.detail) && ok
            ok = show(r.groundHits, "그 뒤에는 땅 기술이 비행 타입에게도 통한다",
                      r.detail2) && ok
        } else { ok = show(false, "떨어뜨리기 검사") && ok }

        print("\n-- 웅크리기 --")
        if let r = await defenseCurlCheck(chart: chart) {
            ok = show(r.boosted, "웅크리기 뒤 데구르르가 두 배가 된다", r.detail) && ok
            ok = show(r.defenseUp, "방어도 오른다", r.detail2) && ok
        } else { ok = show(false, "웅크리기 검사") && ok }

        print("\n-- 트집 --")
        if let r = await probe(move: "torment", user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.tormented, "같은 기술을 연속으로 못 쓰게 된다") && ok
        }

        print("\n-- 사슬묶기 --")
        if let r = await disableCheck(chart: chart) {
            ok = show(r.disabled, "상대가 마지막에 쓴 기술이 봉인된다", r.detail) && ok
        } else { ok = show(false, "사슬묶기 검사") && ok }

        // MARK: 위력이 상황에 따라 정해지는 기술이 **실제로 데미지를 주는가**
        //
        // 이런 기술은 PokéAPI 가 power: null 로 준다. 그것 때문에 "데미지 없는
        // 기술" 로 걸러져 계산이 아예 돌지 않았다 — 위력 공식을 고쳐도
        // 소용이 없었다.
        print("\n-- 위력이 상황에 따라 정해지는 기술 --")
        for name in ["return", "frustration", "gyro-ball", "electro-ball",
                     "flail", "reversal", "wring-out", "psywave",
                     "super-fang", "endeavor"] {
            guard let mv = try? await PokeAPI.shared.move(name) else { continue }
            guard let r = await probe(move: name, user: 143, foe: 151, chart: chart,
                                      setup: { b in b.currentHP = b.maxHP / 4 }) else {
                ok = show(false, "\(mv.display) 실행") && ok; continue
            }
            ok = show(r.foe.currentHP < r.foe.maxHP,
                      "\(mv.display) 이(가) 데미지를 준다",
                      "\(r.foe.maxHP - r.foe.currentHP) 데미지") && ok
        }

        // MARK: 버티기 · 봉인 · 아쿠아링 · 웅크리기 · 위액 · 충전 · 파워트릭 · 헤롱헤롱 · 일격필살
        print("\n-- 버티기 --")
        if let r = await endureCheck(chart: chart) {
            ok = show(r.survived, "치명적인 공격에도 HP 1 로 버틴다", r.detail) && ok
        } else { ok = show(false, "버티기 검사") && ok }

        print("\n-- 봉인 --")
        if let r = await imprisonCheck(chart: chart) {
            ok = show(r.blocked, "같은 기술을 가진 상대는 그 기술을 못 쓴다", r.detail) && ok
        } else { ok = show(false, "봉인 검사") && ok }

        print("\n-- 아쿠아링 --")
        if let r = await twoTurn(first: "aqua-ring", then: "aqua-ring",
                                user: 143, foe: 151, chart: chart,
                                setup: { b in b.currentHP = b.maxHP / 2 }) {
            ok = show(r.user.aquaRing, "물의 베일을 두른다") && ok
            ok = show(r.user.currentHP > r.user.maxHP / 2, "매 턴 회복된다",
                      "\(r.user.currentHP)/\(r.user.maxHP)") && ok
        }

        print("\n-- 웅크리기 --")
        if let r = await probe(move: "minimize", user: 143, foe: 151, chart: chart) {
            ok = show(r.user.evasionStage >= 2, "회피율이 크게 오른다",
                      "\(r.user.evasionStage)") && ok
        }

        print("\n-- 위액 --")
        if let r = await gastroAcidCheck(chart: chart) {
            ok = show(r.suppressed, "상대 특성이 사라진다", r.detail) && ok
        } else { ok = show(false, "위액 검사") && ok }

        print("\n-- 충전 --")
        if let r = await chargeCheck(chart: chart) {
            ok = show(r.doubled, "다음 전기 기술의 위력이 2배가 된다", r.detail) && ok
        } else { ok = show(false, "충전 검사") && ok }

        print("\n-- 파워트릭 --")
        if let r = await probe(move: "power-trick", user: 143, foe: 151, chart: chart) {
            ok = show(r.user.powerTricked, "공격과 방어가 뒤바뀐다") && ok
        }

        print("\n-- 헤롱헤롱 --")
        if let r = await probe(move: "attract", user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.infatuated, "상대가 헤롱헤롱해진다") && ok
        }

        print("\n-- 일격필살 --")
        if let r = await ohkoCheck(chart: chart) {
            ok = show(r.canKO, "맞으면 한 방에 쓰러진다", r.detail) && ok
            ok = show(r.higherLevelImmune, "레벨이 높은 상대에게는 통하지 않는다",
                      r.detail2) && ok
        } else { ok = show(false, "일격필살 검사") && ok }

        // MARK: 난동부리기 · 도발 · 기충전 · 길동무 · 미래예지
        print("\n-- 난동부리기 (조작 불가) --")
        if let r = await probe(move: "outrage", user: 143, foe: 143, chart: chart) {
            ok = show(r.user.isRampaging, "쓰면 묶인다",
                      "남은 \(r.user.rampageTurns)턴") && ok
            ok = show(r.foe.currentHP < r.foe.maxHP, "그 턴에 데미지는 들어간다") && ok
        }
        if let r = await rampageLock(chart: chart) {
            ok = show(r.forced, "묶인 동안 다른 기술을 골라도 같은 기술이 나간다", r.detail) && ok
            ok = show(r.confusedAfter, "끝나면 혼란에 빠진다", r.detail2) && ok
        } else { ok = show(false, "난동부리기 강제 검사") && ok }

        print("\n-- 도발 --")
        if let r = await probe(move: "taunt", user: 94, foe: 143, chart: chart) {
            ok = show(r.foe.tauntTurns > 0, "상대가 도발당한다", "\(r.foe.tauntTurns)턴") && ok
        }
        if let r = await tauntBlocks(chart: chart) {
            ok = show(r.blocked, "도발당하면 변화기를 쓸 수 없다", r.detail) && ok
        } else { ok = show(false, "도발 차단 검사") && ok }

        print("\n-- 기충전 --")
        if let r = await probe(move: "focus-energy", user: 143, foe: 143, chart: chart) {
            ok = show(r.user.focusEnergy, "기합이 들어간다") && ok
            ok = show(r.user.critStage >= 2, "급소 랭크가 오른다",
                      "\(r.user.critStage)") && ok
        }

        print("\n-- 길동무 --")
        if let r = await probe(move: "destiny-bond", user: 94, foe: 143, chart: chart) {
            ok = show(r.user.destinyBond, "길동무 상태가 된다") && ok
        }
        if let r = await destinyBondWorks(chart: chart) {
            ok = show(r.bothFainted, "길동무 상태에서 쓰러지면 상대도 쓰러진다", r.detail) && ok
        } else { ok = show(false, "길동무 효과 검사") && ok }

        print("\n-- 미래예지 --")
        if let r = await probe(move: "future-sight", user: 65, foe: 143, chart: chart) {
            ok = show(r.foe.currentHP == r.foe.maxHP, "쓴 턴에는 데미지가 없다",
                      "\(r.foe.currentHP)/\(r.foe.maxHP)") && ok
        }
        if let r = await futureLands(chart: chart) {
            ok = show(r.landed, "두 턴 뒤에 터진다", r.detail) && ok
        } else { ok = show(false, "미래예지 검사") && ok }

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

    /// 웅크리기가 데구르르의 위력을 두 배로 하는지
    private static func defenseCurlCheck(chart: TypeChart) async -> (
        boosted: Bool, detail: String, defenseUp: Bool, detail2: String
    )? {
        guard let curl = try? await PokeAPI.shared.move("defense-curl"),
              let rollout = try? await PokeAPI.shared.move("rollout"),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }

        func dmg(withCurl: Bool) async -> (Int, Int) {
            // 웅크리기를 쓰고 데구르르 / 그냥 데구르르 — 첫 데구르르 데미지를 비교한다
            let picks = withCurl ? [0, 1] : [1]
            guard let e = await runTurns(userMoves: [curl, rollout], foeMoves: [splash],
                                         picks: picks, userID: 143, foeID: 151,
                                         chart: chart) else { return (-1, 0) }
            let dealt = 9999 - e.state.sides[1].team[0].currentHP
            return (dealt, e.state.sides[0].team[0].stages[.defense] ?? 0)
        }
        let (plain, _) = await dmg(withCurl: false)
        let (curled, def) = await dmg(withCurl: true)
        return (curled > plain, "데구르르 \(plain) → 웅크리기 후 \(curled)",
                def > 0, "방어 랭크 \(def)")
    }

    /// 떨어뜨리기가 비행 타입을 땅으로 끌어내리는지
    private static func smackDownCheck(chart: TypeChart) async -> (
        grounded: Bool, detail: String, groundHits: Bool, detail2: String
    )? {
        guard let smack = try? await PokeAPI.shared.move("smack-down"),
              let quake = try? await PokeAPI.shared.move("earthquake"),
              let splash = try? await PokeAPI.shared.move("splash"),
              let flyer = try? await PokeAPI.shared.species(6) else { return nil }   // 리자몽(비행)

        func make(_ sp: SpeciesDef, _ ms: [MoveDef], _ tag: String, speed: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            b.maxHP = 9999; b.currentHP = 9999
            return b
        }
        guard let me = try? await PokeAPI.shared.species(143) else { return nil }
        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make(me, [smack, quake], "h", speed: 999)],
                                               activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make(flyer, [splash], "g", speed: 1)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 21)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()

        // 1턴: 지진 — 비행 타입이라 통하지 않아야 한다
        let before1 = e.state.sides[1].team[0].currentHP
        e.resolveTurn(hostAction: .useMove(index: 1), guestAction: .useMove(index: 0))
        let quakeBefore = before1 - e.state.sides[1].team[0].currentHP

        // 2턴: 떨어뜨리기
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let grounded = e.state.sides[1].team[0].grounded

        // 3턴: 다시 지진 — 이번엔 통해야 한다
        let before3 = e.state.sides[1].team[0].currentHP
        e.resolveTurn(hostAction: .useMove(index: 1), guestAction: .useMove(index: 0))
        let quakeAfter = before3 - e.state.sides[1].team[0].currentHP

        return (grounded, "땅에 붙음=\(grounded)",
                quakeBefore == 0 && quakeAfter > 0,
                "떨어뜨리기 전 지진 \(quakeBefore) → 후 \(quakeAfter)")
    }

    /// 사슬묶기가 상대의 마지막 기술을 봉인하는지
    private static func disableCheck(chart: TypeChart) async -> (disabled: Bool, detail: String)? {
        guard let disable = try? await PokeAPI.shared.move("disable"),
              let tackle = try? await PokeAPI.shared.move("tackle") else { return nil }
        // 1턴: 상대가 몸통박치기 → 2턴: 내가 사슬묶기 → 상대의 그 기술이 봉인된다
        guard let e = await runTurns(userMoves: [disable, tackle], foeMoves: [tackle],
                                     picks: [1, 0], userID: 94, foeID: 143,
                                     chart: chart) else { return nil }
        let foe = e.state.sides[1].team[0]
        let sawLog = e.state.log.contains { $0.contains("사슬묶기로 봉인") }
        return (foe.disabledTurns > 0 && foe.disabledMoveIndex != nil,
                "봉인 \(foe.disabledTurns)턴 · 로그=\(sawLog)")
    }

    /// 버티기로 살아남는지
    private static func endureCheck(chart: TypeChart) async -> (survived: Bool, detail: String)? {
        guard let endure = try? await PokeAPI.shared.move("endure"),
              let tackle = try? await PokeAPI.shared.move("tackle") else { return nil }
        guard let e = await runTurns(userMoves: [endure], foeMoves: [tackle],
                                     picks: [0], userID: 143, foeID: 143,
                                     chart: chart, userSpeed: 999, hp: 5) else { return nil }
        let me = e.state.sides[0].team[0]
        let sawLog = e.state.log.contains { $0.contains("견뎌냈다") }
        return (me.currentHP == 1 && !me.isFainted,
                "HP \(me.currentHP) · 로그=\(sawLog)")
    }

    /// 봉인이 상대 기술을 막는지
    private static func imprisonCheck(chart: TypeChart) async -> (blocked: Bool, detail: String)? {
        guard let imprison = try? await PokeAPI.shared.move("imprison"),
              let tackle = try? await PokeAPI.shared.move("tackle") else { return nil }
        // 양쪽 다 몸통박치기를 가지고 있다 → 봉인하면 상대가 못 쓴다
        guard let e = await runTurns(userMoves: [imprison, tackle], foeMoves: [tackle],
                                     picks: [0, 1], userID: 143, foeID: 143,
                                     chart: chart) else { return nil }
        let blocked = e.state.log.contains { $0.contains("봉인되어 있다") }
        return (blocked, "차단 로그=\(blocked)")
    }

    /// 위액이 특성을 없애는지
    private static func gastroAcidCheck(chart: TypeChart) async -> (
        suppressed: Bool, detail: String
    )? {
        guard let acid = try? await PokeAPI.shared.move("gastro-acid"),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }
        guard let e = await runTurns(userMoves: [acid], foeMoves: [splash],
                                     picks: [0], userID: 94, foeID: 143,
                                     chart: chart) else { return nil }
        let foe = e.state.sides[1].team[0]
        return (foe.abilitySuppressed,
                "특성무효=\(foe.abilitySuppressed) 반영되는 특성=\(foe.abilityKind)")
    }

    /// 충전이 전기 기술의 위력을 두 배로 하는지
    private static func chargeCheck(chart: TypeChart) async -> (doubled: Bool, detail: String)? {
        guard let charge = try? await PokeAPI.shared.move("charge"),
              let bolt = try? await PokeAPI.shared.move("thunder-shock"),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }

        func dmg(withCharge: Bool) async -> Int {
            let picks = withCharge ? [0, 1] : [1, 1]
            guard let e = await runTurns(userMoves: [charge, bolt], foeMoves: [splash],
                                         picks: picks, userID: 143, foeID: 151,
                                         chart: chart) else { return -1 }
            // 마지막 턴에 들어간 데미지를 본다
            return 9999 - e.state.sides[1].team[0].currentHP
        }
        let base = await dmg(withCharge: false)
        let boosted = await dmg(withCharge: true)
        // 충전 없이 두 번 쏘면 두 번 분량이므로, 한 번 분량과 비교한다
        return (boosted > base / 2 * 3 / 2,
                "충전 없이 2회 \(base) / 충전 후 1회 \(boosted)")
    }

    /// 일격필살이 통하는지 · 레벨이 높은 상대에게 실패하는지
    private static func ohkoCheck(chart: TypeChart) async -> (
        canKO: Bool, detail: String, higherLevelImmune: Bool, detail2: String
    )? {
        guard let sp = try? await PokeAPI.shared.species(143),
              let drill = try? await PokeAPI.shared.move("horn-drill"),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }

        func run(foeLevel: Int) -> (fainted: Bool, log: [String]) {
            func make(_ ms: [MoveDef], _ tag: String, level: Int, speed: Int) -> Battler {
                let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                      rarity: "common", isShiny: false, origin: .dex,
                                      fullyEvolved: true)
                var b = Battler.make(slot: slot, species: sp, moves: ms, level: level)
                for i in b.moves.indices { b.moves[i].ppLeft = 99 }
                b.stats[.speed] = speed
                b.maxHP = 9999; b.currentHP = 9999
                return b
            }
            var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                                 sides: [SideState(playerName: "나",
                                                   team: [make([drill], "h", level: 50, speed: 999)],
                                                   activeIndex: 0),
                                         SideState(playerName: "상대",
                                                   team: [make([splash], "g", level: foeLevel, speed: 1)],
                                                   activeIndex: 0)])
            st.phase = .chooseLead
            // 30% 명중이라 여러 씨드를 돌려 한 번이라도 맞는지 본다
            // 연속된 씨드는 첫 난수가 비슷하게 나올 수 있다 — 크게 흩뿌린다
            for seed in 1...60 {
                var e = BattleEngine(state: st, chart: chart,
                                     seed: UInt64(seed) &* 0x9E3779B97F4A7C15)
                e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
                e.beginBattle()
                e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
                if e.state.sides[1].team[0].isFainted { return (true, e.state.log) }
            }
            return (false, [])
        }
        let same = run(foeLevel: 50)
        let higher = run(foeLevel: 80)
        return (same.fainted, "레벨 같을 때 60회 중 명중=\(same.fainted)",
                !higher.fainted, "레벨 높은 상대 60회 모두 실패=\(!higher.fainted)")
    }

    /// 여러 턴 돌리는 공용 도구 — 내가 지정한 인덱스대로 기술을 쓴다
    private static func runTurns(userMoves: [MoveDef], foeMoves: [MoveDef],
                                 picks: [Int], userID: Int, foeID: Int,
                                 chart: TypeChart, userSpeed: Int = 999,
                                 hp: Int = 9999) async -> BattleEngine? {
        guard let uSp = try? await PokeAPI.shared.species(userID),
              let fSp = try? await PokeAPI.shared.species(foeID) else { return nil }
        func make(_ sp: SpeciesDef, _ ms: [MoveDef], _ tag: String, speed: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            b.maxHP = hp; b.currentHP = hp
            return b
        }
        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make(uSp, userMoves, "h", speed: userSpeed)],
                                               activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make(fSp, foeMoves, "g", speed: 1)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 313)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()
        for p in picks {
            guard case .awaitingMoves = e.state.phase else { break }
            e.resolveTurn(hostAction: .useMove(index: p), guestAction: .useMove(index: 0))
        }
        return e
    }

    /// 난동부리기에 묶인 동안 다른 기술을 골라도 같은 기술이 나가는지
    private static func rampageLock(chart: TypeChart) async -> (
        forced: Bool, detail: String, confusedAfter: Bool, detail2: String
    )? {
        guard let outrage = try? await PokeAPI.shared.move("outrage"),
              let tackle = try? await PokeAPI.shared.move("tackle"),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }
        // 1턴 난동부리기 → 2·3턴은 1번(몸통박치기)을 골라도 역린이 나가야 한다
        guard let e = await runTurns(userMoves: [outrage, tackle], foeMoves: [splash],
                                     picks: [0, 1, 1, 1], userID: 143, foeID: 143,
                                     chart: chart) else { return nil }
        let log = e.state.log
        let outrageCount = log.filter { $0.contains(outrage.display) }.count
        let tackleCount = log.filter { $0.contains("몸통박치기") }.count
        let me = e.state.sides[0].team[0]
        // 묶여 있는 동안만 강제된다 (2~3턴). 풀린 뒤에 다른 기술이 나가는 건 정상이다.
        // 핵심은 **묶인 턴에 내가 고른 기술이 무시되는가** 다.
        return (outrageCount >= 2,
                "\(outrage.display) \(outrageCount)회 (묶인 동안 강제)"
                + " / 풀린 뒤 몸통박치기 \(tackleCount)회",
                me.confusionTurns > 0 || log.contains { $0.contains("혼란에 빠졌다") },
                "혼란 \(me.confusionTurns)턴")
    }

    /// 길동무 상태에서 쓰러지면 쓰러뜨린 쪽도 함께 쓰러지는지
    private static func destinyBondWorks(chart: TypeChart) async -> (
        bothFainted: Bool, detail: String
    )? {
        // 고스트에게 노말 기술은 무효다 — 양쪽 다 노말 타입으로 둔다
        // (그렇게 하지 않으면 상대가 나를 못 쓰러뜨려 검사가 헛돈다)
        guard let bond = try? await PokeAPI.shared.move("destiny-bond"),
              let tackle = try? await PokeAPI.shared.move("tackle"),
              let uSp = try? await PokeAPI.shared.species(143),
              let fSp = try? await PokeAPI.shared.species(143) else { return nil }

        func make(_ sp: SpeciesDef, _ ms: [MoveDef], _ tag: String,
                  speed: Int, hp: Int) -> Battler {
            let slot = RosterSlot(id: tag, speciesID: sp.id, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex,
                                  fullyEvolved: true)
            var b = Battler.make(slot: slot, species: sp, moves: ms, level: 50)
            for i in b.moves.indices { b.moves[i].ppLeft = 99 }
            b.stats[.speed] = speed
            b.maxHP = hp; b.currentHP = hp
            return b
        }
        // 내가 먼저 길동무를 쓰고(빠름), 상대가 나를 쓰러뜨린다(내 HP 1)
        var st = BattleState(rules: BattleRules(maxTeamSize: 1, level: 50),
                             sides: [SideState(playerName: "나",
                                               team: [make(uSp, [bond], "h", speed: 999, hp: 1)],
                                               activeIndex: 0),
                                     SideState(playerName: "상대",
                                               team: [make(fSp, [tackle], "g", speed: 1, hp: 300)],
                                               activeIndex: 0)])
        st.phase = .chooseLead
        var e = BattleEngine(state: st, chart: chart, seed: 88)
        e.setLead(.host, index: 0); e.setLead(.guest, index: 0)
        e.beginBattle()
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))

        let me = e.state.sides[0].team[0]
        let foe = e.state.sides[1].team[0]
        let sawLog = e.state.log.contains { $0.contains("길동무로 삼았다") }
        return (me.isFainted && foe.isFainted,
                "나 쓰러짐=\(me.isFainted) 상대 쓰러짐=\(foe.isFainted) 로그=\(sawLog)")
    }

    /// 도발당한 쪽이 변화기를 쓸 수 없는지
    private static func tauntBlocks(chart: TypeChart) async -> (blocked: Bool, detail: String)? {
        guard let taunt = try? await PokeAPI.shared.move("taunt"),
              let swords = try? await PokeAPI.shared.move("swords-dance"),
              let tackle = try? await PokeAPI.shared.move("tackle") else { return nil }
        // 내가 도발 → 상대는 칼춤(변화기)을 쓰려 하지만 막혀야 한다
        guard let e = await runTurns(userMoves: [taunt, tackle], foeMoves: [swords],
                                     picks: [0, 1], userID: 94, foeID: 143,
                                     chart: chart) else { return nil }
        let blocked = e.state.log.contains { $0.contains("도발당해서") }
        let foe = e.state.sides[1].team[0]
        return (blocked && (foe.stages[.attack] ?? 0) == 0,
                "차단 로그=\(blocked) 상대 공격 랭크=\(foe.stages[.attack] ?? 0)")
    }

    /// 미래예지가 두 턴 뒤에 터지는지
    private static func futureLands(chart: TypeChart) async -> (landed: Bool, detail: String)? {
        guard let fs = try? await PokeAPI.shared.move("future-sight"),
              let splash = try? await PokeAPI.shared.move("splash") else { return nil }
        guard let e = await runTurns(userMoves: [fs, splash], foeMoves: [splash],
                                     picks: [0, 1, 1], userID: 65, foeID: 143,
                                     chart: chart) else { return nil }
        let foeHP = e.state.sides[1].team[0].currentHP
        let landed = e.state.log.contains { $0.contains("덮쳤다") }
        return (landed && foeHP < 9999,
                "터짐 로그=\(landed) 상대 HP=\(foeHP)")
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
