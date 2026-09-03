import SwiftUI

struct PokeBattleBarApp: App {
    var body: some Scene {
        WindowGroup(TestProfile.windowTitle) {
            RootView()
        }
        .defaultSize(width: TestProfile.windowWidth, height: 640)
        .defaultPosition(TestProfile.windowPosition)
    }
}
