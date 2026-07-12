import AVFoundation
import HandPoseCore
import HandTrackingKit
import Observation
import QuartzOutput
import SwiftUI

/// Owns the pipeline lifecycle and permission state. In M1 the pipeline is
/// source → overlay; filters, engine, and pointer output join in M2/M3.
@MainActor
@Observable
final class AppController {
    private(set) var cameraStatus: CameraPermission.Status = .notDetermined
    private(set) var accessibilityGranted = false
    private(set) var isTracking = false
    private(set) var lastError: String?

    /// Newest frame, for the debug overlay's landmark dots.
    private(set) var latestFrame: HandPoseFrame?
    /// Measured delivery rate of hand-pose frames.
    private(set) var framesPerSecond: Double = 0

    private var source: CameraHandPoseSource?
    private var consumeTask: Task<Void, Never>?
    private var permissionPolling: Task<Void, Never>?
    private var fpsEstimator = FrameRateEstimator()

    var hasAllPermissions: Bool {
        cameraStatus == .granted && accessibilityGranted
    }

    /// Menu bar icon state: off / no-permission / tracking.
    var menuBarSystemImage: String {
        if !hasAllPermissions {
            return "hand.raised.slash"
        }
        return isTracking ? "hand.point.up.left.fill" : "hand.point.up.left"
    }

    /// The live capture session, exposed solely so the debug overlay can
    /// attach a preview layer.
    var captureSession: AVCaptureSession? {
        source?.captureSession
    }

    init() {
        refreshPermissions()
        startPermissionPolling()
    }

    // MARK: - Permissions

    func refreshPermissions() {
        cameraStatus = CameraPermission.status
        accessibilityGranted = QuartzPointerOutput.hasAccessibilityPermission

        // A permission revoked mid-run must halt tracking.
        if isTracking && !hasAllPermissions {
            stopTracking()
        }
    }

    func requestCameraAccess() {
        Task {
            await CameraPermission.requestAccess()
            refreshPermissions()
        }
    }

    func requestAccessibilityAccess() {
        QuartzPointerOutput.promptForPermission()
    }

    func openCameraSettings() {
        openSystemSettings(pane: "Privacy_Camera")
    }

    func openAccessibilitySettings() {
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    /// Accessibility grants produce no notification; poll while running.
    private func startPermissionPolling() {
        permissionPolling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refreshPermissions()
            }
        }
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Tracking lifecycle

    func setTracking(_ enabled: Bool) {
        if enabled {
            startTracking()
        } else {
            stopTracking()
        }
    }

    private func startTracking() {
        guard !isTracking, hasAllPermissions else { return }

        let source = CameraHandPoseSource()
        self.source = source
        isTracking = true
        lastError = nil
        fpsEstimator = FrameRateEstimator()

        consumeTask = Task { [weak self] in
            do {
                try await source.start()
                for await frame in source.frames {
                    guard let self, !Task.isCancelled else { break }
                    self.ingest(frame)
                }
            } catch {
                self?.fail(error)
            }
        }
    }

    private func stopTracking() {
        consumeTask?.cancel()
        consumeTask = nil
        source?.stop()
        source = nil
        isTracking = false
        latestFrame = nil
        framesPerSecond = 0
    }

    private func ingest(_ frame: HandPoseFrame) {
        latestFrame = frame
        framesPerSecond = fpsEstimator.record(frame.timestamp)
    }

    private func fail(_ error: Error) {
        lastError = String(describing: error)
        stopTracking()
    }
}
