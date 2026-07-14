import AVFoundation
@testable import HandTrackingKit
import XCTest

final class StableFramingPolicyTests: XCTestCase {
    /// The policy is process-global AVFoundation state (no camera required):
    /// after applying it, the app owns Center Stage and it is off, so OS
    /// auto-framing can never pan/zoom the crop under the tracker.
    func testPolicyTakesAppControlAndDisablesCenterStage() {
        CameraHandPoseSource.applyStableFramingPolicy()
        XCTAssertEqual(AVCaptureDevice.centerStageControlMode, .app)
        XCTAssertFalse(AVCaptureDevice.isCenterStageEnabled)
    }

    /// Applying twice must be harmless — configureIfNeeded can run on every
    /// fresh source instance.
    func testPolicyIsIdempotent() {
        CameraHandPoseSource.applyStableFramingPolicy()
        CameraHandPoseSource.applyStableFramingPolicy()
        XCTAssertEqual(AVCaptureDevice.centerStageControlMode, .app)
        XCTAssertFalse(AVCaptureDevice.isCenterStageEnabled)
    }
}
