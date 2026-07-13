import Foundation

/// UserDefaults keys shared by the settings UI and the pipeline controller.
enum SettingsKeys {
    static let sensitivity = "sensitivity"
    static let tapDuration = "tapDuration"
    static let clickEnabled = "gesture.click.enabled"
    static let dragEnabled = "gesture.drag.enabled"
    static let rightClickEnabled = "gesture.rightClick.enabled"
    static let scrollEnabled = "gesture.scroll.enabled"

    /// Registered at launch so plain `double(forKey:)`/`bool(forKey:)` reads
    /// return these until the user changes something.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            sensitivity: 1.0,
            tapDuration: 0.25,
            clickEnabled: true,
            dragEnabled: true,
            rightClickEnabled: true,
            scrollEnabled: true,
        ])
    }
}
