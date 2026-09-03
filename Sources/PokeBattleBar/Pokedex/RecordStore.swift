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

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/PokeBattleBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 테스트 인스턴스는 별도 파일을 쓴다 — 같은 파일에 두 앱이 쓰면 기록이 덮인다
        fileURL = dir.appending(path: TestProfile.recordFileName)
        if let d = try? Data(contentsOf: fileURL),
           let r = try? JSONDecoder().decode(Record.self, from: d) {
            record = r
        }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(record) { try? d.write(to: fileURL) }
    }

    /// 배틀 결과를 기록하고 이번에 얻은 포인트를 돌려준다.
    @discardableResult
    func finish(won: Bool, draw: Bool, opponent: String,
                survivors: Int, teamSize: Int) -> Int {
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
        persist()
        return gained
    }

    func reset() {
        record = Record()
        persist()
    }
}
