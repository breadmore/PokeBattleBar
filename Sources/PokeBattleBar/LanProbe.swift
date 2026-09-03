import Foundation

/// 같은 맥에서 앱을 두 개 띄웠을 때 서로 방이 보이는지 확인하는 진단.
///
/// 한쪽을 `--lanprobe host`, 다른 쪽을 `--lanprobe browse` 로 **따로 실행**해야
/// 의미가 있다. 한 프로세스 안에서 하는 검사(--nettest)로는
/// 프로세스 경계를 넘는 Bonjour 광고가 실제로 보이는지 알 수 없다.
enum LanProbe {
    static func run(role: String, seconds: Int) async -> Bool {
        let tag = TestProfile.tag ?? "?"
        switch role {
        case "host":
            let host = RoomHost()
            let roomName = "probe-\(tag)"
            host.onError = { print("  ✗ \($0)") }
            host.start(roomName: roomName, hostName: "probe-\(tag)",
                       rules: .default, modeSummary: "진단")
            print("[\(tag)] 방 광고 시작: \(roomName) — \(seconds)초 유지")
            try? await Task.sleep(for: .seconds(seconds))
            host.stop()
            print("[\(tag)] 광고 종료")
            return true

        case "browse":
            let browser = RoomBrowser()
            let seen = SeenRooms()
            browser.onError = { print("  ✗ \($0)") }
            browser.onRooms = { rooms in Task { await seen.add(rooms) } }
            browser.start()
            print("[\(tag)] \(seconds)초 동안 방 검색…")
            try? await Task.sleep(for: .seconds(seconds))
            browser.stop()
            let found = await seen.all
            for r in found {
                print("  · \(r) ")
            }
            // 내가 띄우지 않은 방(다른 프로세스의 방)이 하나라도 보여야 통과
            let others = found.filter { !$0.contains("probe-\(tag)") }
            if others.isEmpty {
                print("  ✗ 다른 프로세스의 방을 찾지 못했습니다 (총 \(found.count)개)")
                return false
            }
            print("  ✓ 다른 프로세스의 방 \(others.count)개 발견 — 같은 맥에서 배틀 가능")
            return true

        default:
            print("사용법: --lanprobe host|browse [--seconds N]")
            return false
        }
    }

    private actor SeenRooms {
        var all: [String] = []
        func add(_ rooms: [DiscoveredRoom]) {
            for r in rooms {
                let line = "\(r.name)  방장 \(r.hostName)  v\(r.protocolVersion)  \(r.occupied ? "사용중" : "대기")"
                if !all.contains(line) { all.append(line) }
            }
        }
    }
}
