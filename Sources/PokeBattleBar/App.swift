import SwiftUI
import AppKit

struct PokeBattleBarApp: App {
    /// 모델을 App 수준에 둔다 — 상단 탭과 창이 **같은 인스턴스**를 봐야
    /// 창을 닫아도 초대와 새 방 알림을 받을 수 있다.
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(TestProfile.windowTitle, id: AppWindow.main) {
            RootView(model: model)
        }
        .defaultSize(width: TestProfile.windowWidth, height: 640)
        .defaultPosition(TestProfile.windowPosition)

        // PokeTokenBar 처럼 상단 탭에 상주한다
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            HStack(spacing: 3) {
                PokeBallIcon(size: 15, monochrome: true)
                if model.unseenNotices > 0 {
                    Text("\(model.unseenNotices)")
                        .font(.system(size: 10, weight: .bold))
                }
            }
        }
    }
}
