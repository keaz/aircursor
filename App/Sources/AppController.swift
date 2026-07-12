import AVFoundation
import GestureEngine
import HandPoseCore
import HandTrackingKit
import MotionFilters
import Observation
import PointerControl
import QuartzOutput
import SwiftUI

/// Owns the pipeline lifecycle and permission state. The M3 pipeline:
/// camera frames → One Euro smoothing of the movement joint → GestureEngine
/// → PointerMapper → QuartzOutput.
@MainActor
@Observable
final class AppController {
    /// One Euro tuning for the movement joint: 1 Hz cutoff at rest kills
    /// jitter; beta lifts the cutoff ~5 Hz per normalized-unit/s of hand
    /// speed so fast motion stays responsive.
    private static let cursorFilterMinCutoff = 1.0
    private static let cursorFilterBeta = 5.0
    private static let cursorFilterDCutoff = 1.0

    private static let sensitivityDefaultsKey = "sensitivity"

    private(set) var cameraStatus: CameraPermission.Status = .notDetermined
    private(set) var accessibilityGranted = false
    private(set) var isTracking = false
    private(set) var lastError: String?

    /// Newest frame, for the debug overlay's landmark dots.
    private(set) var latestFrame: HandPoseFrame?
    /// Measured delivery rate of hand-pose frames.
    private(set) var framesPerSecond: Double = 0
    /// Engine state and index-pinch metric, for the debug overlay HUD.
    private(set) var gestureStateLabel = "idle"
    private(set) var indexPinchMetric: Double?

    private var source: CameraHandPoseSource?
    private var consumeTask: Task<Void, Never>?
    private var permissionPolling: Task<Void, Never>?
    private var fpsEstimator = FrameRateEstimator()

    // Pipeline stages.
    private let output = QuartzPointerOutput()
    private var engine = GestureEngine()
    private var mapper: PointerMapper?
    private var movementFilter = PointOneEuroFilter()

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
        observeDisplayConfigurationChanges()
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
        engine = GestureEngine()
        mapper = makeMapper()
        resetMovementFilter()

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
        // The safety invariant survives teardown: resetting the engine
        // mid-drag yields the button-releasing intents; post them before
        // discarding the pipeline.
        let releaseIntents = engine.reset()
        if let timestamp = latestFrame?.timestamp {
            post(commands(for: releaseIntents, at: timestamp))
        }

        consumeTask?.cancel()
        consumeTask = nil
        source?.stop()
        source = nil
        isTracking = false
        latestFrame = nil
        framesPerSecond = 0
        gestureStateLabel = "idle"
        indexPinchMetric = nil
        mapper = nil
        resetMovementFilter()
    }

    private func ingest(_ frame: HandPoseFrame) {
        latestFrame = frame
        framesPerSecond = fpsEstimator.record(frame.timestamp)

        let intents = engine.consume(smoothingMovementJoint(of: frame))
        post(commands(for: intents, at: frame.timestamp))

        gestureStateLabel = Self.label(for: engine.state)
        indexPinchMetric = engine.lastMetrics.index
    }

    private func fail(_ error: Error) {
        lastError = String(describing: error)
        stopTracking()
    }

    // MARK: - Pipeline stages

    /// Replaces the movement joint with its One Euro-smoothed position, so
    /// the engine's moveBy deltas are jitter-free while the raw fingertip
    /// geometry keeps pinch detection crisp.
    private func smoothingMovementJoint(of frame: HandPoseFrame) -> HandPoseFrame {
        guard let point = frame.joints[engine.config.movementJoint] else { return frame }
        var joints = frame.joints
        joints[engine.config.movementJoint] = movementFilter.filter(point, at: frame.timestamp)
        return HandPoseFrame(joints: joints, timestamp: frame.timestamp)
    }

    private func commands(
        for intents: [PointerIntent], at timestamp: TimeInterval
    ) -> [PointerCommand] {
        intents.flatMap { mapper?.commands(for: $0, at: timestamp) ?? [] }
    }

    private func makeMapper() -> PointerMapper {
        let storedSensitivity = UserDefaults.standard.double(forKey: Self.sensitivityDefaultsKey)
        var config = PointerConfig()
        config.sensitivity = storedSensitivity > 0 ? storedSensitivity : 1.0
        return PointerMapper(
            config: config,
            displayBounds: QuartzDisplays.activeDisplayBounds(),
            currentPointerLocation: { QuartzPointerOutput.currentPointerLocation() }
        )
    }

    private func resetMovementFilter() {
        movementFilter = PointOneEuroFilter(
            minCutoff: Self.cursorFilterMinCutoff,
            beta: Self.cursorFilterBeta,
            dCutoff: Self.cursorFilterDCutoff
        )
    }

    private static func label(for state: GestureEngine.State) -> String {
        switch state {
        case .idle: return "idle"
        case .tracking: return "tracking"
        case .pinched(kind: .index, _, _): return "pinched (index)"
        case .pinched(kind: .middle, _, _): return "pinched (middle)"
        case .dragging: return "dragging"
        case .scrolling: return "scrolling"
        }
    }

    private func observeDisplayConfigurationChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.displayConfigurationDidChange()
            }
        }
    }

    private func displayConfigurationDidChange() {
        let commands = mapper?.displayConfigurationChanged(QuartzDisplays.activeDisplayBounds()) ?? []
        post(commands)
    }

    private func post(_ commands: [PointerCommand]) {
        guard !commands.isEmpty else { return }
        do {
            for command in commands {
                try output.apply(command)
            }
        } catch {
            lastError = "Pointer output failed: \(String(describing: error))"
        }
    }
}
