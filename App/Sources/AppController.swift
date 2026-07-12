import AVFoundation
import HandPoseCore
import HandTrackingKit
import MotionFilters
import Observation
import PointerControl
import QuartzOutput
import SwiftUI

/// Owns the pipeline lifecycle and permission state. In M2 the pipeline is
/// source → One Euro smoothing → PointerMapper → QuartzOutput behind a debug
/// flag; the gesture engine joins in M3.
@MainActor
@Observable
final class AppController {
    /// One Euro tuning for the M2 cursor path: 1 Hz cutoff at rest kills
    /// jitter; beta lifts the cutoff ~5 Hz per normalized-unit/s of hand
    /// speed so fast motion stays responsive. Revisit during M3 tuning.
    private static let cursorFilterMinCutoff = 1.0
    private static let cursorFilterBeta = 5.0
    private static let cursorFilterDCutoff = 1.0

    private static let moveDebugDefaultsKey = "debug.alwaysEngagedMove"
    private static let sensitivityDefaultsKey = "sensitivity"

    private(set) var cameraStatus: CameraPermission.Status = .notDetermined
    private(set) var accessibilityGranted = false
    private(set) var isTracking = false
    private(set) var lastError: String?

    /// Newest frame, for the debug overlay's landmark dots.
    private(set) var latestFrame: HandPoseFrame?
    /// Measured delivery rate of hand-pose frames.
    private(set) var framesPerSecond: Double = 0

    /// Temporary M2 debug mode: while tracking, the cursor follows the
    /// smoothed index-MCP point as if the clutch were always engaged.
    /// Removed in M3 when the gesture engine takes over.
    var moveCursorDebugEnabled = UserDefaults.standard.bool(forKey: moveDebugDefaultsKey) {
        didSet {
            UserDefaults.standard.set(moveCursorDebugEnabled, forKey: Self.moveDebugDefaultsKey)
            if !moveCursorDebugEnabled {
                disengageCursorDrive()
            }
        }
    }

    private var source: CameraHandPoseSource?
    private var consumeTask: Task<Void, Never>?
    private var permissionPolling: Task<Void, Never>?
    private var fpsEstimator = FrameRateEstimator()

    // M2 cursor-drive pipeline stages.
    private let output = QuartzPointerOutput()
    private var mapper: PointerMapper?
    private var cursorFilter = PointOneEuroFilter()
    private var previousSmoothedPoint: CGPoint?
    private var cursorEngaged = false

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
        mapper = makeMapper()
        resetCursorDrive()

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
        mapper = nil
        resetCursorDrive()
    }

    private func ingest(_ frame: HandPoseFrame) {
        latestFrame = frame
        framesPerSecond = fpsEstimator.record(frame.timestamp)
        driveCursorDebug(with: frame)
    }

    private func fail(_ error: Error) {
        lastError = String(describing: error)
        stopTracking()
    }

    // MARK: - M2 debug cursor drive (removed in M3)

    /// Always-engaged relative movement: smooth the index MCP, feed deltas
    /// through the mapper, post the resulting moves. Hand loss disengages so
    /// re-acquisition re-anchors instead of jumping.
    private func driveCursorDebug(with frame: HandPoseFrame) {
        guard moveCursorDebugEnabled, isTracking else { return }

        guard let indexMCP = frame.joints[.indexMCP] else {
            disengageCursorDrive(at: frame.timestamp)
            return
        }

        let smoothed = cursorFilter.filter(indexMCP, at: frame.timestamp)
        defer { previousSmoothedPoint = smoothed }

        guard cursorEngaged, let previous = previousSmoothedPoint else {
            _ = mapper?.commands(for: .engaged, at: frame.timestamp)
            cursorEngaged = true
            return
        }

        let commands = mapper?.commands(
            for: .moveBy(dx: smoothed.x - previous.x, dy: smoothed.y - previous.y),
            at: frame.timestamp
        ) ?? []
        post(commands)
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

    private func resetCursorDrive() {
        cursorFilter = PointOneEuroFilter(
            minCutoff: Self.cursorFilterMinCutoff,
            beta: Self.cursorFilterBeta,
            dCutoff: Self.cursorFilterDCutoff
        )
        previousSmoothedPoint = nil
        cursorEngaged = false
    }

    private func disengageCursorDrive(at timestamp: TimeInterval? = nil) {
        if cursorEngaged {
            _ = mapper?.commands(for: .disengaged, at: timestamp ?? Date.timeIntervalSinceReferenceDate)
        }
        resetCursorDrive()
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
            moveCursorDebugEnabled = false
        }
    }
}
