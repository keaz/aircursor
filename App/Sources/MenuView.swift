import SwiftUI

/// Menu bar popover: the onboarding checklist until both permissions exist,
/// then the tracking controls.
struct MenuView: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if controller.hasAllPermissions {
                controls
            } else {
                OnboardingView(controller: controller)
            }

            Divider()

            HStack {
                Button("Settings…") {
                    openSettings()
                    NSApplication.shared.activate()
                }
                .keyboardShortcut(",")

                Spacer()

                Button("Quit") {
                    controller.shutdown() // release held input before quitting
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.menuBarSystemImage)
                .foregroundStyle(.tint)
            Text("AirCursor")
                .font(.headline)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if !controller.hasAllPermissions { return "needs permissions" }
        if controller.isTracking {
            return String(format: "%.0f fps · %@", controller.framesPerSecond, controller.gestureStateLabel)
        }
        return "paused"
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

            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Debug Overlay…") {
                openWindow(id: WindowID.debugOverlay)
                NSApplication.shared.activate()
            }
            .keyboardShortcut("d")
        }
    }
}
