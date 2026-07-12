import HandTrackingKit
import SwiftUI

/// Two-step permission checklist with live status. The pipeline cannot start
/// until both are granted.
struct OnboardingView: View {
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AirCursor needs two permissions")
                .font(.headline)

            PermissionRow(
                title: "Camera",
                detail: "Tracks your hand. Video never leaves this Mac.",
                granted: controller.cameraStatus == .granted
            ) {
                if controller.cameraStatus == .notDetermined {
                    Button("Allow…") { controller.requestCameraAccess() }
                } else {
                    Button("Open Settings…") { controller.openCameraSettings() }
                }
            }

            PermissionRow(
                title: "Accessibility",
                detail: "Lets AirCursor move the pointer.",
                granted: controller.accessibilityGranted
            ) {
                Button("Request…") { controller.requestAccessibilityAccess() }
                Button("Open Settings…") { controller.openAccessibilitySettings() }
            }

            Text("Tracking unlocks automatically once both are granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionRow<Actions: View>: View {
    let title: String
    let detail: String
    let granted: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !granted {
                    HStack(spacing: 8) { actions }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
