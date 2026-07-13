import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.sensitivity) private var sensitivity = 1.0
    @AppStorage(SettingsKeys.tapDuration) private var tapDuration = 0.25
    @AppStorage(SettingsKeys.leftButtonEnabled) private var leftButtonEnabled = true
    @AppStorage(SettingsKeys.rightButtonEnabled) private var rightButtonEnabled = true
    @AppStorage(SettingsKeys.scrollEnabled) private var scrollEnabled = true
    @AppStorage(SettingsKeys.zoomEnabled) private var zoomEnabled = true
    @AppStorage(SettingsKeys.swipesEnabled) private var swipesEnabled = true
    @AppStorage(SettingsKeys.missionControlEnabled) private var missionControlEnabled = true

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
            }

            Section {
                LabeledContent {
                    Slider(value: $tapDuration, in: 0.15...0.5, step: 0.05)
                } label: {
                    Text("Tap duration")
                    Text(String(format: "%.0f ms", tapDuration * 1000))
                        .monospacedDigit()
                }
            } footer: {
                Text("How quickly a two-finger flick must complete to count as a right-click tap rather than a scroll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $leftButtonEnabled) {
                    Text("Click & drag")
                    Text("Pinch thumb + index while pointing")
                }
                Toggle(isOn: $rightButtonEnabled) {
                    Text("Right click")
                    Text("Quick two-finger tap")
                }
                Toggle(isOn: $scrollEnabled) {
                    Text("Scroll")
                    Text("Two fingers extended, stroke up or down")
                }
                Toggle(isOn: $zoomEnabled) {
                    Text("Zoom in")
                    Text("Pinch from a relaxed hand, then spread")
                }
                Toggle(isOn: $swipesEnabled) {
                    Text("Switch Spaces")
                    Text("Open palm, flick left or right")
                }
                Toggle(isOn: $missionControlEnabled) {
                    Text("Mission Control")
                    Text("Snap a fist open into all five fingers")
                }
            } header: {
                Text("Gestures")
            } footer: {
                Text("Pointer movement (index-finger pointing) is always on. Changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
