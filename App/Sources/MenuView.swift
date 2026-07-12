import SwiftUI

/// Menu bar popover: the onboarding checklist until both permissions exist,
/// then the tracking controls.
struct MenuView: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.hasAllPermissions {
                controls
            } else {
                OnboardingView(controller: controller)
            }

            Divider()

            Button("Quit AirCursor") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Track hand",
                isOn: Binding(
                    get: { controller.isTracking },
                    set: { controller.setTracking($0) }
                )
            )
            .toggleStyle(.switch)

            // Temporary M2 debug mode; the gesture engine replaces it in M3.
            Toggle(
                "Move cursor (M2 debug)",
                isOn: Binding(
                    get: { controller.moveCursorDebugEnabled },
                    set: { controller.moveCursorDebugEnabled = $0 }
                )
            )
            .toggleStyle(.checkbox)
            .help("Always-engaged mode: the cursor follows your hand while tracking runs.")

            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Debug Overlay…") {
                openWindow(id: WindowID.debugOverlay)
                NSApplication.shared.activate()
            }
        }
    }
}
