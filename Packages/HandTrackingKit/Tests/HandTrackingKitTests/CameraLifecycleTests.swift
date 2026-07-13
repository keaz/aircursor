import Foundation
@testable import HandTrackingKit
import XCTest

/// The stop/start cancellation race: turning tracking off while the camera
/// is mid-authorization must never leave the session running.
final class CameraLifecycleTests: XCTestCase {
    /// Lets the test observe when `start()` reaches authorization and control
    /// when it returns.
    private final class AuthGate: @unchecked Sendable {
        let entered = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)

        func authorize() async -> Bool {
            entered.signal()
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    self.proceed.wait()
                    cont.resume()
                }
            }
            return true
        }
    }

    func testStopBeforeStartCompletesNeverStartsTheSession() async throws {
        let gate = AuthGate()
        let source = CameraHandPoseSource(
            minimumJointConfidence: 0.3,
            targetFrameRate: 60,
            requestAuthorization: { await gate.authorize() }
        )

        let startTask = Task { try await source.start() }
        gate.entered.wait()   // start() is now suspended inside authorization
        source.stop()         // turn tracking off before authorization returns
        gate.proceed.signal() // let authorization return

        do {
            try await startTask.value
            XCTFail("start() should throw after a preceding stop()")
        } catch is CancellationError {
            // expected — the stop won the race
        }

        // Let any queued session work drain, then confirm nothing started.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(source.sessionStartCount, 0, "the session must not start after stop()")
    }

    func testRepeatedStopIsIdempotent() async throws {
        let source = CameraHandPoseSource()
        source.stop()
        source.stop()
        source.stop()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(source.sessionStartCount, 0)
    }
}
