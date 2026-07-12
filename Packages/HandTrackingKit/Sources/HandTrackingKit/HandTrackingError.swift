/// Failures starting or running the live camera source.
public enum HandTrackingError: Error, Equatable, Sendable {
    case cameraPermissionDenied
    case noCameraAvailable
    case captureConfigurationFailed(String)
}
