import Foundation

/// 승패 기록과 포인트. 로컬에 저장한다.
actor RecordStore {
    static let shared = RecordStore()

    struct Record: Codable, Sendable {
        var wins = 0
        var losses = 0
        var draws = 0
        var points = 0
        var bestStreak = 0
        var currentStreak = 0
        /// 상대별 전적
        var byOpponent: [String: Head] = [:]

        struct Head: Codable, Sendable {
            var wins = 0
            var losses = 0
        }

        /// 대전 한 판의 기록.
        ///
        /// 무엇으로 싸웠고 어떻게 끝났는지 나중에 볼 수 있어야 한다 —
        /// 승패 숫자만으로는 그 배틀이 어땠는지 알 수 없다.
        struct Battle: Codable, Sendable, Identifiable {
            var id = UUID()
            var at = Date()
            var opponent: String
            /// nil = 무승부
            var won: Bool?
            var points: Int
            var turns: Int
            var mode: String

            /// 내가 데려간 포켓몬 (쓰러진 순서가 아니라 팀 순서)
            var myTeam: [Mon]
            var foeTeam: [Mon]

            /// 배틀이 끝난 시점에 **마지막까지 남아 있던** 포켓몬
            var myLastStanding: Mon?
            var foeLastStanding: Mon?

            var myRemaining: Int { myTeam.filter { !$0.fainted }.count }
            var foeRemaining: Int { foeTeam.filter { !$0.fainted }.count }

            struct Mon: Codable, Sendable, Hashable, Identifiable {
                var id = UUID()
                var speciesID: Int
                var name: String
                var fainted: Bool
                var hpLeft: Int
                var maxHP: Int
                var isShiny: Bool
                /// 메가·거다이맥스·원시회귀 등으로 바뀐 폼 (스프라이트용)
                var form: String?
            }
        }

        /// 지난 대전 기록 (최근 것이 뒤). 너무 쌓이지 않게 잘라 둔다.
        var history: [Battle] = []

        var total: Int { wins + losses + draws }
        var winRate: Double { total == 0 ? 0 : Double(wins) / Double(total) }
    }

    /// 승리 포인트 계산.
    /// 이긴 것 자체 + 남긴 포켓몬 + 연승 보너스.
    static func pointsFor(win: Bool, draw: Bool, survivors: Int, teamSize: Int,
                          streakAfter: Int) -> Int {
        guard !draw else { return 5 }
        guard win else { return 1 }          // 져도 참가 포인트
        var p = 10
        p += survivors * 3                  // 많이 남길수록
        if teamSize > 0, survivors == teamSize { p += 5 }   // 무손실
        p += max(0, min(10, (streakAfter - 1) * 2))         // 연승 보너스 (상한 있음)
        return p
    }

    private let fileURL: URL
    private(set) var record = Record()

    /// 저장 폴더 (실제 앱과 테스트가 같은 곳을 쓴다 — 파일 이름만 다르다)
    static var storageDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/PokeBattleBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// - Parameter fileName: 쓸 파일 이름.
    ///
    ///   **검증 코드는 반드시 자기 파일 이름을 넘겨야 한다.** 예전에는 이
    ///   생성자가 무조건 실제 `record.json` 을 열었고, 그래서 `--testall` 을
    ///   돌릴 때마다 테스트가 사용자의 전적에 가짜 승리를 더하고
    ///   `clearHistory()` 로 **대전기록을 전부 지웠다.**
    init(fileName: String = TestProfile.recordFileName) {
        fileURL = Self.storageDir.appending(path: fileName)
        if let d = try? Data(contentsOf: fileURL),
           let r = try? JSONDecoder().decode(Record.self, from: d) {
            record = r
        }
    }

    /// 검증용 임시 저장소. 실제 기록 파일을 절대 건드리지 않는다.
    ///
    /// 이름에 `-test-` 가 들어가야 `TestProfile.fileName` 규칙과 어긋나지 않고,
    /// 사용자가 폴더를 봤을 때도 무엇인지 알 수 있다.
    static func forTesting(_ tag: String) -> RecordStore {
        RecordStore(fileName: "record-test-\(tag).json")
    }

    /// 검증이 끝난 뒤 임시 파일을 지운다
    func removeFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 이 저장소가 쓰는 파일 이름 (검증에서 실제 파일이 아닌지 확인하는 데 쓴다)
    var fileName: String { fileURL.lastPathComponent }

    private func persist() {
        if let d = try? JSONEncoder().encode(record) { try? d.write(to: fileURL) }
    }

    /// 배틀 결과를 기록하고 이번에 얻은 포인트를 돌려준다.
    /// 대전 한 판을 기록에 남긴다 (승패 집계 + 지난 대전 목록)
    @discardableResult
    func finish(won: Bool, draw: Bool, opponent: String,
                survivors: Int, teamSize: Int,
                battle: Record.Battle? = nil) -> Int {
        if draw {
            record.draws += 1
            record.currentStreak = 0
        } else if won {
            record.wins += 1
            record.currentStreak += 1
            record.bestStreak = max(record.bestStreak, record.currentStreak)
            record.byOpponent[opponent, default: .init()].wins += 1
        } else {
            record.losses += 1
            record.currentStreak = 0
            record.byOpponent[opponent, default: .init()].losses += 1
        }
        let gained = Self.pointsFor(win: won, draw: draw, survivors: survivors,
                                    teamSize: teamSize, streakAfter: record.currentStreak)
        record.points += gained
        if var b = battle {
            b.points = gained
            record.history.append(b)
            // 너무 쌓이면 파일이 커진다 — 최근 100 판만 남긴다
            if record.history.count > 100 {
                record.history.removeFirst(record.history.count - 100)
            }
        }
        persist()
        return gained
    }

    /// 지난 대전 목록만 지운다 (승패·포인트는 남긴다)
    func clearHistory() {
        record.history = []
        persist()
    }

    func reset() {
        record = Record()
        persist()
    }
}
