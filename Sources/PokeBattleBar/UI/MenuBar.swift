import SwiftUI
import AppKit

/// 몬스터볼 아이콘.
///
/// 원작 에셋을 쓸 수 없으므로 코드로 그린다 — 위 절반, 아래 절반, 띠, 중앙 버튼.
/// 상단 탭에서는 아주 작게 그려지므로 선 굵기를 크기에 비례시켜야 뭉개지지 않는다.
struct PokeBallIcon: View {
    var size: CGFloat = 18
    /// 상단 탭용 단색 모드 — 메뉴바는 색을 쓰면 튄다
    var monochrome = false

    var body: some View {
        let band = max(1, size * 0.11)
        let button = size * 0.28

        ZStack {
            Circle()
                .fill(monochrome ? AnyShapeStyle(.primary.opacity(0.18))
                                 : AnyShapeStyle(Color(red: 0.94, green: 0.94, blue: 0.95)))
            // 위 절반
            Circle()
                .fill(monochrome ? AnyShapeStyle(.primary)
                                 : AnyShapeStyle(Color(red: 0.88, green: 0.22, blue: 0.18)))
                .mask(alignment: .top) {
                    Rectangle().frame(height: size / 2)
                }
            // 가운데 띠
            Rectangle()
                .fill(.primary)
                .frame(height: band)
            // 중앙 버튼
            Circle()
                .fill(monochrome ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
                .frame(width: button, height: button)
                .overlay(Circle().stroke(.primary, lineWidth: band * 0.8))
            Circle().stroke(.primary, lineWidth: band * 0.9)
        }
        .frame(width: size, height: size)
    }
}

/// 상단 탭(메뉴바) 내용.
///
/// PokeTokenBar 처럼 상주하면서, 창을 닫아도 초대와 새 방 알림을 받을 수 있게 한다.
struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("배틀 창 열기") { showWindow() }
                .keyboardShortcut("o")

            Divider()

            // 초대가 왔으면 여기서 바로 받을 수 있어야 한다
            if let inv = model.incomingInvite {
                Text("\(inv.from) 님의 초대")
                Button("수락하고 들어가기") {
                    showWindow()
                    Task { await model.acceptInvite() }
                }
                Button("거절") { model.declineInvite() }
                Divider()
            }

            Text(statusLine)

            if model.lobbyPeers.isEmpty {
                Text("로비에 다른 사람이 없습니다")
            } else {
                Menu("로비 \(model.lobbyPeers.count)명") {
                    ForEach(model.lobbyPeers) { p in
                        // 초대는 방을 연 뒤에만 보낼 수 있다
                        if model.canInvite && p.status.invitable && p.compatible
                            && !model.invitesSent.contains(p.displayName) {
                            Button("\(p.displayName) 초대하기") {
                                showWindow()
                                Task { await model.invite(p) }
                            }
                        } else {
                            Text("\(p.displayName) — \(peerNote(p))")
                        }
                    }
                    if !model.canInvite {
                        Divider()
                        Text("초대하려면 먼저 방을 열어주세요")
                    }
                }
            }

            if !model.discovered.isEmpty {
                Menu("열린 방 \(model.discovered.count)개") {
                    ForEach(model.discovered) { r in
                        Button("\(r.hostName) · 최대 \(r.teamCap)마리") {
                            showWindow()
                            Task { await model.join(r) }
                        }
                        .disabled(r.occupied || !r.compatible)
                    }
                }
            }

            if !model.notices.isEmpty {
                Divider()
                Menu("알림 \(model.notices.count)개") {
                    ForEach(model.notices.reversed().prefix(12)) { n in
                        Text(n.text)
                    }
                    Divider()
                    Button("알림 지우기") { model.clearNotices() }
                }
            }

            Divider()
            Toggle("Dock 아이콘 숨기기", isOn: Binding(
                get: { model.hideDockIcon },
                set: { model.setHideDockIcon($0) }
            ))
            Button("종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var statusLine: String {
        switch model.screen {
        case .loading:      "준비 중…"
        case .lobby:        "로비 — \(model.roster.count)마리 보유"
        case .hostingRoom:  "방을 열고 기다리는 중"
        case .joiningRoom:  "접속 중…"
        case .chooseLead:   "선봉 고르는 중"
        case .battle:       "배틀 중 — \(model.opponentName)"
        case .result:        "배틀 종료"
        }
    }

    private func peerNote(_ p: LobbyPeer) -> String {
        if !p.compatible { return "버전 다름 (v\(p.protocolVersion))" }
        if model.invitesSent.contains(p.displayName) { return "초대 보냄" }
        return p.status.ko
    }

    private func showWindow() {
        model.markNoticesSeen()
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: AppWindow.main)
    }
}

enum AppWindow {
    static let main = "pokebattlebar-main"
}

/// 로비 알림 토스트 — 새 방이 열렸거나 초대가 왔을 때 화면 위에 잠깐 뜬다.
struct NoticeToast: View {
    let notice: AppModel.Notice
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            icon
            Text(notice.text).font(.callout.bold())
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.background)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(tint.opacity(0.55), lineWidth: 1.5)
        )
    }

    private var tint: Color {
        switch notice.kind {
        case .newRoom:  .blue
        case .invite:   .orange
        case .declined: .secondary
        case .info:     .secondary
        }
    }

    @ViewBuilder private var icon: some View {
        switch notice.kind {
        case .newRoom:  PokeBallIcon(size: 16)
        case .invite:   Image(systemName: "envelope.fill").foregroundStyle(.orange)
        case .declined: Image(systemName: "hand.raised.fill").foregroundStyle(.secondary)
        case .info:     Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
    }
}

/// 초대 받았을 때 뜨는 확인창
struct InviteSheet: View {
    let model: AppModel
    let invite: AppModel.Invite

    var body: some View {
        VStack(spacing: 16) {
            PokeBallIcon(size: 44)
            VStack(spacing: 4) {
                Text("\(invite.from) 님의 배틀 초대")
                    .font(.title3.bold())
                Text(invite.roomName).font(.callout).foregroundStyle(.secondary)
            }
            Text("수락하면 바로 그 방으로 들어갑니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("거절") { model.declineInvite() }
                Button("수락") { Task { await model.acceptInvite() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(minWidth: 320)
    }
}

/// 업데이트 버튼.
///
/// 새 버전이 없으면 조용히 사라진다 — 늘 회색 버튼이 있으면 눈에 걸린다.
/// 프로토콜 버전이 다르면 배틀 자체가 안 되므로, 있을 때는 확실히 보이게 한다.
struct UpdateButton: View {
    let model: AppModel
    @State private var showNotes = false

    var body: some View {
        if let u = model.availableUpdate {
            Button {
                showNotes = true
            } label: {
                HStack(spacing: 5) {
                    if model.updateDownloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("업데이트").font(.system(size: 11, weight: .heavy))
                        Text("v\(u.version)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(GB.hilite))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.updateDownloading)
            .help("새 버전 v\(u.version) 이 있습니다")
            .popover(isPresented: $showNotes, arrowEdge: .bottom) {
                UpdatePopover(model: model, update: u)
            }
        }
    }
}

struct UpdatePopover: View {
    let model: AppModel
    let update: UpdateChecker.Update

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                PokeBallIcon(size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("새 버전 v\(update.version)")
                        .font(.headline)
                    Text("지금 v\(model.appVersion) · 프로토콜 v\(model.protocolVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Text("동료와 배틀하려면 **양쪽 버전이 같아야** 합니다. "
                 + "한쪽만 새 버전이면 방 목록에 \"버전 불일치\" 로 표시됩니다.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            if !update.notes.isEmpty {
                ScrollView {
                    Text(update.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }

            if let s = model.updateStatus {
                Text(s).font(.caption.bold()).foregroundStyle(.orange)
            }

            HStack {
                Button("릴리스 페이지") { NSWorkspace.shared.open(update.pageURL) }
                Spacer()
                Button(model.updateDownloading ? "받는 중…" : "지금 업데이트") {
                    Task { await model.downloadAndRunUpdate() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.updateDownloading)
            }

            Text("업데이트하면 앱이 잠깐 닫히고 다시 열립니다. "
                 + "전적·기술·도구 설정은 그대로 유지됩니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 330)
    }
}
