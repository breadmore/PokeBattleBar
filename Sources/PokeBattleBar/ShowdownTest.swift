import Foundation

/// `PokeBattleBar --showdowntest`
/// Showdown 데이터 통합과 새 기능(기술 선택·추천 세팅·포인트)을 검증한다.
enum ShowdownTest {
    static func run() async -> Bool {
        print("=== Showdown 데이터 · 신규 기능 검증 ===\n")
        var ok = true

        // MARK: 데이터 적재
        print("-- 데이터 --")
        ok = show(Showdown.moves.count > 900, "기술 데이터 적재", "\(Showdown.moves.count)개") && ok
        ok = show(Showdown.sets.count > 400, "추천 세팅 적재", "\(Showdown.sets.count)종") && ok
        ok = show(Showdown.pokeAPIMoveNames.count > 900, "PokeAPI 이름 목록",
                  "\(Showdown.pokeAPIMoveNames.count)개") && ok

        // MARK: 이름 변환
        print("\n-- 이름 변환 --")
        ok = show(Showdown.id(fromPokeAPI: "thunder-wave") == "thunderwave",
                  "PokeAPI → Showdown id") && ok
        ok = show(Showdown.pokeAPIName(fromDisplay: "Body Slam") == "body-slam",
                  "표시명 → PokeAPI 이름") && ok

        // MARK: 플래그 — 예전에 손으로 관리하던 것들
        print("\n-- 기술 플래그 (예전 수기 목록 대체) --")
        ok = show(MoveFlags.isContact("tackle"), "몸통박치기 = 접촉") && ok
        ok = show(!MoveFlags.isContact("flamethrower"), "화염방사 = 비접촉") && ok
        ok = show(MoveFlags.isContact("play-rough"), "플레어드라이브류도 접촉으로 잡힌다") && ok
        ok = show(MoveFlags.isPunch("fire-punch"), "불꽃펀치 = 펀치") && ok
        ok = show(MoveFlags.isPunch("meteor-mash"), "코멧펀치 = 펀치 (수기 목록엔 있었나?)") && ok
        ok = show(MoveFlags.isBite("crunch"), "깨물어부수기 = 물기") && ok
        ok = show(MoveFlags.isSound("boomburst"), "폭음파 = 소리") && ok
        ok = show(MoveFlags.isPowder("spore"), "버섯포자 = 가루") && ok

        let contactCount = Showdown.moves.values.filter(\.isContact).count
        ok = show(contactCount > 250, "접촉 기술 수", "\(contactCount)개 (수기 목록은 ~100개였다)") && ok

        // MARK: 자기 교체 / 자폭
        print("\n-- 자기 교체 · 자폭 --")
        for m in ["u-turn", "volt-switch", "flip-turn", "baton-pass", "parting-shot"] {
            ok = show(MoveFlags.isSelfSwitch(m), "\(m) = 자기 교체") && ok
        }
        ok = show(!MoveFlags.isSelfSwitch("tackle"), "몸통박치기는 교체 아님") && ok
        for m in ["explosion", "self-destruct", "misty-explosion"] {
            ok = show(MoveFlags.isSelfDestruct(m), "\(m) = 자폭") && ok
        }
        ok = show(!MoveFlags.isSelfDestruct("double-edge"), "이판사판태클은 자폭 아님") && ok

        // MARK: 방어 관통
        print("\n-- 방어 관통 --")
        ok = show(!MoveFlags.bypassesProtect("tackle"), "몸통박치기는 방어로 막힌다") && ok
        ok = show(MoveFlags.bypassesProtect("feint"), "페인트는 방어를 관통한다") && ok

        // MARK: 손가락흔들기 풀
        print("\n-- 손가락흔들기 --")
        let pool = Showdown.metronomePool
        ok = show(pool.count > 500, "부를 수 있는 기술", "\(pool.count)개 (수기 목록은 207개)") && ok
        ok = show(!pool.contains("metronome"), "자기 자신은 제외") && ok
        ok = show(!pool.contains { $0.hasPrefix("max-") }, "맥스 기술 제외") && ok
        ok = show(pool.allSatisfy { Showdown.pokeAPIMoveNames.contains($0) },
                  "전부 PokeAPI 로 받을 수 있는 이름") && ok

        // MARK: 추천 세팅
        print("\n-- 실전 추천 세팅 --")
        // 원본은 gen9 랜덤배틀 풀(509종) 이라 **모든 종에 추천이 있는 게 아니다.**
        // 후딘·토게피처럼 빠진 종이 있는 건 데이터의 사실이지 버그가 아니다.
        // 그래서 "있는 종은 제대로 나오는가" 와 "없으면 없다고 하는가" 를 나눠 본다.
        for name in ["Snorlax", "Charizard", "Mew", "Gengar", "Swalot"] {
            if let s = Showdown.set(forSpeciesName: name) {
                print("  ✓ \(name): 기술 \(s.movePool.count)개"
                      + (s.item.map { ", 도구 \($0)" } ?? "")
                      + (s.abilities.isEmpty ? "" : ", 특성 \(s.abilities.joined(separator: "/"))"))
            } else {
                print("  ✗ \(name) 세팅 없음"); ok = false
            }
        }
        ok = show(Showdown.set(forSpeciesName: "Alakazam") == nil,
                  "풀에 없는 종은 추천이 없다고 답한다 (후딘)") && ok
        ok = show(Showdown.set(forSpeciesName: "NotAPokemon") == nil,
                  "존재하지 않는 종은 nil") && ok
        // 이름 형식이 달라도 같은 결과가 나와야 한다
        ok = show(Showdown.set(forSpeciesName: "snorlax") != nil
                  && Showdown.set(forSpeciesName: "Snorlax") != nil,
                  "대소문자·표시명 모두 조회된다") && ok
        if let snor = Showdown.set(forSpeciesName: "Snorlax") {
            ok = show(snor.movePool.contains("body-slam"),
                      "잠만보 추천에 몸통박치기 포함", "\(snor.movePool.prefix(4))") && ok
            ok = show(snor.movePool.allSatisfy { !$0.contains(" ") },
                      "추천 기술 이름이 PokeAPI 형식") && ok
        }

        // MARK: 포인트 계산
        print("\n-- 승리 포인트 --")
        let win = RecordStore.pointsFor(win: true, draw: false, survivors: 3, teamSize: 6, streakAfter: 1)
        let perfect = RecordStore.pointsFor(win: true, draw: false, survivors: 6, teamSize: 6, streakAfter: 1)
        let streak = RecordStore.pointsFor(win: true, draw: false, survivors: 3, teamSize: 6, streakAfter: 4)
        let lose = RecordStore.pointsFor(win: false, draw: false, survivors: 0, teamSize: 6, streakAfter: 0)
        ok = show(win > lose, "이기면 더 많이 받는다", "\(lose) → \(win)") && ok
        ok = show(perfect > win, "많이 남길수록 더 받는다", "\(win) → \(perfect)") && ok
        ok = show(streak > win, "연승 보너스", "\(win) → \(streak)") && ok
        ok = show(lose > 0, "져도 참가 포인트", "\(lose)") && ok

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }
}
