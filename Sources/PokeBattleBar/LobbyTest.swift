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

        print("\n-- 초대는 방을 연 뒤에만 --")
        m.screen = .lobby
        ok = show(!m.canInvite, "로비에서는 초대할 수 없다") && ok
        m.screen = .hostingRoom
        ok = show(m.canInvite, "방을 열면 초대할 수 있다") && ok
        m.screen = .battle
        ok = show(!m.canInvite, "배틀 중에는 초대할 수 없다") && ok
        m.screen = .chooseLead
        ok = show(!m.canInvite, "선봉 고르는 중에는 초대할 수 없다") && ok

        // 로비에서 부르면 아무 일도 없어야 한다 (방을 몰래 열어버리면 안 된다)
        m.screen = .lobby
        let peer = LobbyPeer(id: "z#9", displayName: "상대", status: .free,
                             endpoint: endpoint, protocolVersion: PokeBattleProtocol.version)
        await m.invite(peer)
        ok = show(m.invitesSent.isEmpty, "로비에서 초대를 눌러도 보내지 않는다",
                  "\(m.invitesSent)") && ok
        ok = show(m.screen == .lobby, "초대가 방을 몰래 열지 않는다", "\(m.screen)") && ok
        ok = show(m.status.contains("방을 열어주세요"), "왜 안 되는지 알려준다", m.status) && ok

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

        print("\n-- 대전기록 --")
        // 승패 숫자만 남기면 그 배틀이 어땠는지 알 수 없다.
        // 무엇으로 싸웠고 누가 끝까지 남았는지 들어가는지 본다.
        let mon = { (id: Int, name: String, fainted: Bool, hp: Int) in
            RecordStore.Record.Battle.Mon(speciesID: id, name: name, fainted: fainted,
                                          hpLeft: hp, maxHP: 200, isShiny: false, form: nil)
        }
        let sample = RecordStore.Record.Battle(
            opponent: "동료",
            won: true,
            points: 0,
            turns: 14,
            mode: "일반",
            myTeam: [mon(143, "잠만보", false, 87), mon(94, "팬텀", true, 0)],
            foeTeam: [mon(65, "후딘", true, 0), mon(151, "뮤", true, 0)],
            myLastStanding: mon(143, "잠만보", false, 87),
            foeLastStanding: nil
        )
        ok = show(sample.myRemaining == 1, "내 남은 마리 수를 센다", "\(sample.myRemaining)") && ok
        ok = show(sample.foeRemaining == 0, "상대 남은 마리 수를 센다", "\(sample.foeRemaining)") && ok
        ok = show(sample.myLastStanding?.name == "잠만보",
                  "끝까지 남은 포켓몬이 들어간다", sample.myLastStanding?.name ?? "없음") && ok
        ok = show(sample.foeTeam.allSatisfy(\.fainted), "전멸한 쪽은 전부 쓰러진 것으로") && ok

        // 실제로 저장되고 다시 읽히는가
        let store = RecordStore()
        let histBefore = await store.record.history.count
        _ = await store.finish(won: true, draw: false, opponent: "동료",
                               survivors: 1, teamSize: 2, battle: sample)
        let after = await store.record
        ok = show(after.history.count == histBefore + 1, "기록이 쌓인다",
                  "\(histBefore) → \(after.history.count)") && ok
        if let last = after.history.last {
            ok = show(last.points > 0, "포인트가 기록에 들어간다", "\(last.points)P") && ok
            ok = show(last.myTeam.count == 2 && last.foeTeam.count == 2,
                      "양쪽 팀이 다 들어간다") && ok
            ok = show(last.turns == 14, "턴 수가 남는다", "\(last.turns)턴") && ok
        }
        await store.clearHistory()
        let cleared = await store.record
        ok = show(cleared.history.isEmpty, "기록만 지울 수 있다") && ok
        ok = show(cleared.wins > 0, "지워도 승패는 남는다", "\(cleared.wins)승") && ok

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
