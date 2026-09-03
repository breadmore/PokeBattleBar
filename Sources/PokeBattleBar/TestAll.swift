import Foundation

/// `PokeBattleBar --testall [--battles N] [--verbose]`
/// 모든 검증 스위트를 순서대로 돌리고 요약표를 출력한다.
/// 하나라도 실패하면 종료코드 1 — 릴리즈 스크립트가 이걸 보고 배포를 막는다.
enum TestAll {
    struct Suite {
        var flag: String
        var name: String
        var what: String
        var run: () async -> Bool
    }

    static func run(battles: Int, verbose: Bool) async -> Bool {
        let suites: [Suite] = [
            .init(flag: "--selftest", name: "엔진 기본", what: "스탯 공식·상성표·전투 종료·조사") {
                await SelfTest.run(speciesA: [87, 317, 6, 9, 3, 65],
                                   speciesB: [143, 130, 149, 94, 68, 131],
                                   level: 50, verbose: verbose)
            },
            .init(flag: "--formaudit", name: "특수 개체·폼", what: "도감 범위 특수 폼 지원 여부") {
                // 전 범위는 오래 걸리므로 스위트에서는 400 까지만 본다
                await FormAudit.run(upTo: 400, verbose: false)
            },
            .init(flag: "--settest", name: "실전 세팅", what: "도구 포함·중복 방지·성격 불변") {
                await MainActor.run { () -> Task<Bool, Never> in
                    Task { await SmogonSetTest.run() }
                }.value
            },
            .init(flag: "--scriptedtest", name: "손구현 기술", what: "잠자기·저주·배북·대타출동·2턴·반동") {
                await ScriptedMoveTest.run(verbose: verbose)
            },
            .init(flag: "--lobbytest", name: "로비·초대", what: "접속자 상태·새 방 알림·배지") {
                await MainActor.run { () -> Task<Bool, Never> in
                    Task { await LobbyTest.run() }
                }.value
            },
            .init(flag: "--playbacktest", name: "턴 재생 연출", what: "결과 프레임 노출·로그 시점") {
                await MainActor.run { () -> Task<Bool, Never> in
                    Task { await PlaybackTest.run() }
                }.value
            },
            .init(flag: "--profiletest", name: "테스트 프로필", what: "두 인스턴스 격리·지정 팀 파싱") {
                await TestProfileTest.run()
            },
            .init(flag: "--movetest", name: "기술 효과", what: "반동·흡수·상태이상·랭크·고정데미지·자폭") {
                await MoveEffectTest.run(verbose: verbose)
            },
            .init(flag: "--formtest", name: "특수 변신", what: "메가·다이맥스·거다이맥스·Z 횟수 규칙") {
                await FormTest.run(verbose: verbose)
            },
            .init(flag: "--pickertest", name: "포켓몬 선택", what: "부분 선택·선봉·교체 인덱스") {
                await MainActor.run { () -> Task<Bool, Never> in
                    Task { await SelectionTest.run() }
                }.value
            },
            .init(flag: "--itemtest", name: "도구 데이터", what: "메가스톤 파싱·Z크리스탈 18타입·효과 매핑") {
                await ItemTest.run()
            },
            .init(flag: "--loadouttest", name: "도구·특성 효과", what: "실제 배틀 계산 반영 30항목") {
                await LoadoutTest.run(verbose: verbose)
            },
            .init(flag: "--extendedtest", name: "날씨·접촉·G-Max", what: "PokeAPI 에 없어 직접 넣은 것들") {
                await ExtendedTest.run()
            },
            .init(flag: "--edgetest", name: "엣지 케이스", what: "포켓몬 엔진에서 자주 틀리는 지점") {
                await EdgeCaseTest.run(verbose: verbose)
            },
            .init(flag: "--bugsweep", name: "불변식 스윕", what: "무작위 배틀 \(battles)회, 매 턴 규칙 검사") {
                await BugSweep.run(battles: battles, verbose: verbose)
            },
            .init(flag: "--showdowntest", name: "Showdown 데이터", what: "플래그·추천세팅·포인트") {
                await ShowdownTest.run()
            },
            .init(flag: "--formchangetest", name: "폼 체인지·재생", what: "폼 선택·자동 변신·스프라이트·턴 스텝") {
                await FormChangeTest.run()
            },
            .init(flag: "--berrytest", name: "나무열매·특성", what: "열매 38종·먹보·긴장감·해감액·봉인·트레이스·무게") {
                await BerryTest.run()
            },
            .init(flag: "--abilitytest", name: "특성 구현률", what: "등장 가능한 특성 중 반영 비율") {
                await AbilityCoverageTest.run(full: false)
            },
            .init(flag: "--modetest", name: "게임 모드", what: "토게피 손가락흔들기·자유의지·랜덤기술·자동변신") {
                await ModeTest.run()
            },
            .init(flag: "--nettest", name: "네트워크", what: "Bonjour·프레이밍·직렬화·버전") {
                await NetTest.run()
            },
        ]

        var results: [(Suite, Bool, Double)] = []
        for (i, s) in suites.enumerated() {
            print(String(repeating: "═", count: 62))
            print("[\(i + 1)/\(suites.count)] \(s.name)  \(s.flag)")
            print("        \(s.what)")
            print(String(repeating: "═", count: 62))
            let t0 = Date()
            let ok = await s.run()
            results.append((s, ok, Date().timeIntervalSince(t0)))
            print()
        }

        // 요약
        print(String(repeating: "═", count: 62))
        print("요약")
        print(String(repeating: "═", count: 62))
        let nameWidth = results.map(\.0.name.count).max() ?? 12
        for (s, ok, dt) in results {
            let pad = String(repeating: " ", count: max(0, nameWidth - s.name.count))
            print("  \(ok ? "✓" : "✗")  \(s.name)\(pad)  \(s.flag.padding(toLength: 16, withPad: " ", startingAt: 0))"
                  + String(format: "%6.1f초", dt))
        }
        let passed = results.filter(\.1).count
        let total = results.count
        let elapsed = results.reduce(0.0) { $0 + $1.2 }
        print()
        print("  \(passed)/\(total) 통과   총 \(String(format: "%.1f", elapsed))초")
        if passed < total {
            print("\n  실패: " + results.filter { !$0.1 }.map(\.0.flag).joined(separator: " "))
        }
        print(String(repeating: "═", count: 62))
        return passed == total
    }
}
