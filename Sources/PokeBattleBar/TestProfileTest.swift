import Foundation

/// 테스트 프로필이 **배포본에 영향을 주지 않는지**, 그리고 두 인스턴스를
/// 실제로 격리하는지 검증한다.
enum TestProfileTest {
    static func run() async -> Bool {
        print("=== 테스트 프로필 ===\n")
        var ok = true
        func show(_ cond: Bool, _ label: String, _ detail: String = "") -> Bool {
            print("  \(cond ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
            return cond
        }

        print("-- 프로필이 없으면 기존과 완전히 같다 --")
        ok = show(TestProfile.sanitize(nil) == nil, "환경변수 없음 → 프로필 없음") && ok
        ok = show(TestProfile.sanitize("") == nil, "빈 문자열 → 프로필 없음") && ok
        ok = show(TestProfile.recordFileName(tag: nil) == "record.json",
                  "기록 파일은 record.json", TestProfile.recordFileName(tag: nil)) && ok
        ok = show(TestProfile.windowTitle(tag: nil) == "PokeBattleBar",
                  "창 제목에 표시가 붙지 않는다", TestProfile.windowTitle(tag: nil)) && ok
        ok = show(TestProfile.decorate(playerName: "영훈", tag: nil) == "영훈",
                  "플레이어 이름이 그대로다") && ok
        ok = show(TestProfile.parseTeam(nil) == nil, "지정 팀 없음 → 도감을 읽는다") && ok

        print("\n-- 프로필이 있으면 격리된다 --")
        ok = show(TestProfile.recordFileName(tag: "A") != TestProfile.recordFileName(tag: "B"),
                  "A 와 B 의 기록 파일이 다르다",
                  "\(TestProfile.recordFileName(tag: "A")) / \(TestProfile.recordFileName(tag: "B"))") && ok
        ok = show(TestProfile.recordFileName(tag: "A") != "record.json",
                  "테스트 기록이 실제 기록을 덮지 않는다") && ok
        ok = show(TestProfile.windowTitle(tag: "A") != TestProfile.windowTitle(tag: "B"),
                  "창 제목으로 두 인스턴스를 구분할 수 있다") && ok
        ok = show(TestProfile.decorate(playerName: "영훈", tag: "A") == "영훈-A",
                  "로비에서 내 방을 알아볼 수 있다") && ok

        print("\n-- 인스턴스마다 따로 써야 하는 파일 --")
        for base in ["record.json", "loadouts.json", "movesets.json"] {
            ok = show(TestProfile.fileName(base, tag: nil) == base,
                      "배포본은 \(base) 그대로") && ok
            let a = TestProfile.fileName(base, tag: "A")
            let b = TestProfile.fileName(base, tag: "B")
            ok = show(a != b && a != base && b != base,
                      "\(base) 가 A/B 로 갈린다", "\(a) / \(b)") && ok
            ok = show(a.hasSuffix(".json"), "확장자가 남는다", a) && ok
        }

        print("\n-- 창 배치 --")
        ok = show(TestProfile.windowPosition(tag: nil) == .center,
                  "배포본은 화면 중앙 (기존과 같다)") && ok
        ok = show(TestProfile.windowPosition(tag: "A") != TestProfile.windowPosition(tag: "B"),
                  "A 와 B 는 서로 다른 자리에 뜬다") && ok
        ok = show(TestProfile.windowWidth == 860 || TestProfile.isTest,
                  "배포본 창 크기는 그대로") && ok

        print("\n-- 프로필 이름 정리 --")
        ok = show(TestProfile.sanitize("../../etc") == "etc",
                  "경로 문자를 지운다", TestProfile.sanitize("../../etc") ?? "nil") && ok
        ok = show(TestProfile.sanitize("///") == nil, "영숫자가 없으면 프로필 없음") && ok
        ok = show((TestProfile.sanitize(String(repeating: "x", count: 40))?.count ?? 0) == 16,
                  "이름 길이를 16자로 자른다") && ok
        // 정리된 이름이 파일 경로를 벗어나지 않아야 한다
        let bad = TestProfile.recordFileName(tag: TestProfile.sanitize("../../evil") ?? "x")
        ok = show(!bad.contains("/") && !bad.contains(".."),
                  "기록 파일 이름이 디렉토리를 벗어나지 않는다", bad) && ok

        print("\n-- 지정 팀 파싱 --")
        ok = show(TestProfile.parseTeam("94,555,479") == [94, 555, 479],
                  "쉼표 구분", "\(TestProfile.parseTeam("94,555,479") ?? [])") && ok
        ok = show(TestProfile.parseTeam(" 94 , 555 ") == [94, 555], "공백 허용") && ok
        ok = show(TestProfile.parseTeam("1,2,3,4,5,6,7,8") == [1, 2, 3, 4, 5, 6],
                  "6마리까지만") && ok
        ok = show(TestProfile.parseTeam("0,9999,94") == [94],
                  "범위를 벗어난 번호는 버린다", "\(TestProfile.parseTeam("0,9999,94") ?? [])") && ok
        ok = show(TestProfile.parseTeam("리자몽") == nil, "숫자가 없으면 무시") && ok

        print("\n-- 실제 로스터를 만들 수 있는가 --")
        if let ids = TestProfile.parseTeam("555,479,351") {
            var built = 0
            for id in ids where (try? await PokeAPI.shared.species(id)) != nil { built += 1 }
            ok = show(built == ids.count, "지정한 종을 모두 불러온다", "\(built)/\(ids.count)") && ok
        }

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }
}
