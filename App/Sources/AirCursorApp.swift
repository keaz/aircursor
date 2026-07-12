import SwiftUI

@main
struct AirCursorApp: App {
    var body: some Scene {
        MenuBarExtra("AirCursor", systemImage: "hand.point.up.left") {
            MenuView()
        }
    }
}

struct MenuView: View {
    var body: some View {
        Text("AirCursor")
        Divider()
        Button("Quit AirCursor") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
