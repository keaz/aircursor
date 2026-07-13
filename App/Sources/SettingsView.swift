import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.sensitivity) private var sensitivity = 1.0
    @AppStorage(SettingsKeys.tapDuration) private var tapDuration = 0.25
    @AppStorage(SettingsKeys.clickEnabled) private var clickEnabled = true
    @AppStorage(SettingsKeys.dragEnabled) private var dragEnabled = true
    @AppStorage(SettingsKeys.rightClickEnabled) private var rightClickEnabled = true
    @AppStorage(SettingsKeys.scrollEnabled) private var scrollEnabled = true

    var body: some View {
        Form {
            Section("Pointer") {
                LabeledContent {
                    Slider(value: $sensitivity, in: 0.3...3.0, step: 0.1)
                } label: {
                    Text("Sensitivity")
                    Text(String(format: "%.1f×", sensitivity))
                        .monospacedDigit()
                }

                LabeledContent {
                    Slider(value: $tapDuration, in: 0.15...0.5, step: 0.05)
                } label: {
                    Text("Tap duration")
                    Text(String(format: "%.0f ms", tapDuration * 1000))
                        .monospacedDigit()
                }
            }

            Section {
                Toggle("Left click", isOn: $clickEnabled)
                Toggle("Drag", isOn: $dragEnabled)
                Toggle("Right click", isOn: $rightClickEnabled)
                Toggle("Scroll", isOn: $scrollEnabled)
            } header: {
                Text("Gestures")
            } footer: {
                Text("Pointer movement (thumb–index pinch clutch) is always on. Changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
