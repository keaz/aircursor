import SwiftUI

enum WindowID {
    static let debugOverlay = "debug-overlay"
}

@main
struct AirCursorApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller)
        } label: {
            Image(systemName: controller.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)

        Window("AirCursor Debug", id: WindowID.debugOverlay) {
            OverlayView(controller: controller)
        }
        .defaultSize(width: 500, height: 480)
    }
}
