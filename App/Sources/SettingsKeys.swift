import Foundation

/// UserDefaults keys shared by the settings UI and the pipeline controller.
enum SettingsKeys {
    static let sensitivity = "sensitivity"
    static let tapDuration = "tapDuration"
    static let leftButtonEnabled = "gesture.leftButton.enabled"
    static let rightButtonEnabled = "gesture.rightButton.enabled"
    static let scrollEnabled = "gesture.scroll.enabled"
    static let zoomEnabled = "gesture.zoom.enabled"
    static let swipesEnabled = "gesture.swipes.enabled"
    static let missionControlEnabled = "gesture.missionControl.enabled"

    /// Registered at launch so plain `double(forKey:)`/`bool(forKey:)` reads
    /// return these until the user changes something.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            sensitivity: 1.0,
            tapDuration: 0.25, // matches GestureConfig.tapDuration
            leftButtonEnabled: true,
            rightButtonEnabled: true,
            scrollEnabled: true,
            zoomEnabled: true,
            swipesEnabled: true,
            missionControlEnabled: true,
        ])
    }
}
