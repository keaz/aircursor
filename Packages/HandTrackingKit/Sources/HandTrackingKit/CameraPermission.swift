import AVFoundation

/// Camera authorization, wrapped so the app never handles AVFoundation types
/// for permission state.
public enum CameraPermission {
    public enum Status: Equatable, Sendable {
        case notDetermined
        case granted
        case denied
    }

    public static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    /// Triggers the system camera prompt when undetermined; otherwise returns
    /// the current state.
    @discardableResult
    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
