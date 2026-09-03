import Foundation

/// 로비(존재 알림·초대·알림) 검증.
enum LobbyTest {
    @MainActor
    static func run() async -> Bool {
        print("=== 로비 · 초대 ===\n")
        var ok = true
        func show(_ c: Bool, _ label: String, _ detail: String = "") -> Bool {
            print("  \(c ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
            return c
        }

        print("-- 상태 표시 --")
        ok = show(PeerStatus.free.invitable, "로비에 있는 사람은 초대할 수 있다") && ok
        ok = show(!PeerStatus.battling.invitable, "배틀 중인 사람은 초대하지 않는다") && ok
        ok = show(!PeerStatus.hosting.invitable, "이미 방을 연 사람은 초대하지 않는다") && ok
        for st in [PeerStatus.free, .hosting, .battling] {
            ok = show(!st.ko.isEmpty, "\(st.rawValue) 한글 표시", st.ko) && ok
        }

        print("\n-- 버전이 다른 상대 --")
        let endpoint = NWEndpointStub.make()
        let old = LobbyPeer(id: "x#1", displayName: "구버전", status: .free,
                            endpoint: endpoint, protocolVersion: PokeBattleProtocol.version - 1)
        let now = LobbyPeer(id: "y#2", displayName: "같은버전", status: .free,
                            endpoint: endpoint, protocolVersion: PokeBattleProtocol.version)
        ok = show(!old.compatible, "버전이 다르면 호환 아님") && ok
        ok = show(now.compatible, "같은 버전이면 호환") && ok

        print("\n-- 알림 쌓기 --")
        let m = AppModel()
        m.screen = .lobby
        ok = show(m.unseenNotices == 0, "처음엔 안 본 알림이 없다") && ok

        // 방이 새로 열리면 알림이 뜬다 (첫 검색 결과는 알리지 않는다)
        m.simulateRoomScan([])                    // 첫 스캔 — 기준선
        m.simulateRoomScan([("영훈의 방", "영훈")])
        ok = show(m.notices.count == 1, "새 방 하나에 알림 하나", "\(m.notices.count)") && ok
        ok = show(m.notices.last?.kind == .newRoom, "종류가 새 방") && ok
        ok = show(m.notices.last?.text.contains("영훈") ?? false,
                  "누구 방인지 들어간다", m.notices.last?.text ?? "") && ok
        ok = show(m.unseenNotices == 1, "안 본 알림 수가 오른다", "\(m.unseenNotices)") && ok
        ok = show(m.toast != nil, "토스트가 뜬다") && ok

        // 같은 방을 다시 봐도 또 알리지 않는다
        m.simulateRoomScan([("영훈의 방", "영훈")])
        ok = show(m.notices.count == 1, "같은 방을 두 번 알리지 않는다", "\(m.notices.count)") && ok

        // 내 방은 알리지 않는다
        let before = m.notices.count
        m.simulateRoomScan([("영훈의 방", "영훈"), ("\(m.playerName)의 방", m.playerName)])
        ok = show(m.notices.count == before, "내 방은 알리지 않는다", "\(m.notices.count)") && ok

        m.markNoticesSeen()
        ok = show(m.unseenNotices == 0, "확인하면 배지가 사라진다") && ok
        m.clearNotices()
        ok = show(m.notices.isEmpty, "알림 지우기") && ok

        print("\n-- 배틀 중에는 방해하지 않는다 --")
        m.screen = .battle
        m.simulateRoomScan([("다른방", "다른사람")])
        ok = show(m.notices.isEmpty, "배틀 중에는 새 방 알림을 띄우지 않는다",
                  "\(m.notices.count)") && ok

        print("\n-- 상단 탭 배지 --")
        m.screen = .lobby
        m.simulateRoomScan([])
        m.simulateRoomScan([("a", "갑"), ("b", "을")])
        ok = show(m.unseenNotices == 2, "방 두 개면 배지도 2", "\(m.unseenNotices)") && ok

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }
}

/// 테스트에서 NWEndpoint 가 필요할 때 — 실제 연결은 하지 않는다
import Network
enum NWEndpointStub {
    static func make() -> NWEndpoint {
        .service(name: "stub", type: pokeLobbyServiceType, domain: "local.", interface: nil)
    }
}
