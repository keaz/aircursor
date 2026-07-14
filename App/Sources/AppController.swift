import AVFoundation
import GestureEngine
import HandPoseCore
import HandTrackingKit
import MotionFilters
import Observation
import os
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

    private(set) var cameraStatus: CameraPermission.Status = .notDetermined
    private(set) var accessibilityGranted = false
    private(set) var isTracking = false
    private(set) var lastError: String?

    /// Landmark-fixture recording (debug overlay). Landmarks only, never
    /// camera frames.
    private(set) var isRecordingFixture = false
    /// Authoritative count mirrored from the recorder, so the UI can never
    /// claim more frames than are saved.
    private(set) var recordedFrameCount = 0
    /// The recording hit its frame cap (`FrameRecorder.maxFrames`).
    private(set) var recordingReachedLimit = false
    private let recorder = FrameRecorder()
    /// The recorder's session token for the active recording. Set only after
    /// the awaited `beginRecording()` completes, so frames feed and count
    /// only against a session whose buffer has been cleared. `nil` while no
    /// recording is armed.
    private var recordingSession: Int?

    /// Newest frame, for the debug overlay's landmark dots.
    private(set) var latestFrame: HandPoseFrame?
    /// Measured delivery rate of hand-pose frames.
    private(set) var framesPerSecond: Double = 0
    /// Inter-frame gap distribution over the last 5 s, for the debug HUD:
    /// the engine's debounce thresholds are frame counts, so the *delivered*
    /// rate and its stability decide what those thresholds mean in seconds.
    private(set) var frameTiming: FrameTimingStatistics.Snapshot?
    /// Engine state and index-pinch metric, for the debug overlay HUD.
    private(set) var gestureStateLabel = "idle"
    private(set) var indexPinchMetric: Double?

    private var source: CameraHandPoseSource?
    private var consumeTask: Task<Void, Never>?
    private var permissionPolling: Task<Void, Never>?
    private var timingStats = FrameTimingStatistics()
    private var lastTimingLog: TimeInterval = 0
    private static let timingLogger = Logger(subsystem: "AirCursor", category: "timing")

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
        observeSettingsChanges()
        observeAppTermination()
    }

    /// Idempotent teardown for app termination. Releases any held input
    /// (button-up, scroll-ended, disengage) before stopping the camera and
    /// tasks — the same teardown safety invariant the engine enforces, so
    /// quitting mid-drag or mid-scroll can never strand the interaction.
    /// Safe to call more than once and whether or not tracking is active.
    func shutdown() {
        stopTracking()
    }

    /// Any normal termination path releases held input, not just the menu's
    /// Quit button.
    private func observeAppTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // willTerminate is delivered synchronously on the main thread, so
            // the release events post before the process exits.
            MainActor.assumeIsolated { self?.shutdown() }
        }
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
        timingStats = FrameTimingStatistics()
        frameTiming = nil
        lastTimingLog = 0
        engine = GestureEngine()
        mapper = makeMapper()
        resetMovementFilter()
        applyTunables()

        consumeTask = Task { [weak self] in
            do {
                try await source.start()
                for await frame in source.frames {
                    guard let self, !Task.isCancelled else { break }
                    await self.ingest(frame)
                }
            } catch is CancellationError {
                // Tracking was turned off during startup; nothing to report.
            } catch {
                // Only the current source's task may surface an error — a
                // stale generation must not disturb a fresh session.
                guard let self, !Task.isCancelled, self.source === source else { return }
                self.fail(error)
            }
        }
    }

    private func stopTracking() {
        cancelRecordingIfActive()

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
        frameTiming = nil
        gestureStateLabel = "idle"
        indexPinchMetric = nil
        mapper = nil
        resetMovementFilter()
    }

    private func ingest(_ frame: HandPoseFrame) async {
        latestFrame = frame
        timingStats.record(frame.timestamp)
        let timing = timingStats.snapshot()
        frameTiming = timing
        framesPerSecond = timing?.framesPerSecond ?? 0
        logTimingPeriodically(timing, at: frame.timestamp)

        // Frames are fed only once the recorder has acknowledged begin (the
        // session token is set), so nothing is recorded before the buffer is
        // armed and cleared.
        if isRecordingFixture, let session = recordingSession {
            let result = await recorder.record(frame, session: session)
            guard result.accepted else { return } // stale session; ignore
            recordedFrameCount = result.frameCount
            if result.reachedLimit {
                recordingReachedLimit = true
                finishRecording() // cap hit → save what we have
            }
        }

        let intents = engine.consume(smoothingMovementJoint(of: frame))
        post(commands(for: intents, at: frame.timestamp))

        gestureStateLabel = Self.label(for: engine.state)
        indexPinchMetric = engine.lastSnapshot?.indexPinchMetric
    }

    /// One unified-log line every ~5 s so a normal session records the real
    /// delivered rate. Read it with:
    /// `log show --predicate 'subsystem == "AirCursor"' --last 10m`.
    private func logTimingPeriodically(
        _ timing: FrameTimingStatistics.Snapshot?, at timestamp: TimeInterval
    ) {
        guard let timing, timestamp - lastTimingLog >= 5 else { return }
        lastTimingLog = timestamp
        Self.timingLogger.notice(
            """
            delivered \(timing.framesPerSecond, format: .fixed(precision: 1), privacy: .public) fps · \
            gap p50 \(timing.medianGap * 1000, format: .fixed(precision: 1), privacy: .public) ms \
            p95 \(timing.p95Gap * 1000, format: .fixed(precision: 1), privacy: .public) ms \
            max \(timing.maxGap * 1000, format: .fixed(precision: 1), privacy: .public) ms · \
            \(timing.longGapCount, privacy: .public) long gaps in \(timing.frameCount, privacy: .public) frames
            """
        )
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
        var config = PointerConfig()
        config.sensitivity = UserDefaults.standard.double(forKey: SettingsKeys.sensitivity)
        return PointerMapper(
            config: config,
            displayBounds: QuartzDisplays.activeDisplayBounds(),
            currentPointerLocation: { QuartzPointerOutput.currentPointerLocation() }
        )
    }

    // MARK: - Settings

    /// Settings apply immediately: sensitivity flows to the mapper, the
    /// per-gesture enables to the engine.
    private func applyTunables() {
        let defaults = UserDefaults.standard
        mapper?.config.sensitivity = defaults.double(forKey: SettingsKeys.sensitivity)

        var engineConfig = engine.config
        engineConfig.tapDuration = defaults.double(forKey: SettingsKeys.tapDuration)
        engineConfig.leftButtonEnabled = defaults.bool(forKey: SettingsKeys.leftButtonEnabled)
        engineConfig.rightButtonEnabled = defaults.bool(forKey: SettingsKeys.rightButtonEnabled)
        engineConfig.scrollEnabled = defaults.bool(forKey: SettingsKeys.scrollEnabled)
        engineConfig.zoomEnabled = defaults.bool(forKey: SettingsKeys.zoomEnabled)
        engineConfig.swipesEnabled = defaults.bool(forKey: SettingsKeys.swipesEnabled)
        engineConfig.missionControlEnabled = defaults.bool(forKey: SettingsKeys.missionControlEnabled)
        engine.config = engineConfig
    }

    private func observeSettingsChanges() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyTunables()
            }
        }
    }

    // MARK: - Fixture recording (debug overlay)

    func toggleFixtureRecording() {
        if isRecordingFixture {
            finishRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecordingFixture = true
        recordedFrameCount = 0
        recordingReachedLimit = false
        recordingSession = nil
        Task { @MainActor [weak self] in
            let token = await self?.recorder.beginRecording()
            guard let self, let token else { return }
            // If tracking stopped or the user toggled off while begin was in
            // flight, retire this session immediately.
            guard self.isRecordingFixture else {
                await self.recorder.cancelRecording(session: token)
                return
            }
            self.recordingSession = token
        }
    }

    /// Stopping tracking discards an in-progress recording rather than
    /// stranding the UI in an active state with no way to save.
    private func cancelRecordingIfActive() {
        guard isRecordingFixture else { return }
        isRecordingFixture = false
        recordedFrameCount = 0
        recordingReachedLimit = false
        let session = recordingSession
        recordingSession = nil
        if let session {
            Task { await recorder.cancelRecording(session: session) }
        }
        // If begin was still in flight (session == nil), startRecording's
        // guard cancels the session once it lands.
    }

    private func finishRecording() {
        isRecordingFixture = false
        let session = recordingSession
        recordingSession = nil
        guard let session else {
            // Begin never completed — nothing was recorded.
            recordedFrameCount = 0
            recordingReachedLimit = false
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }

            let panel = NSSavePanel()
            panel.title = "Save Landmark Fixture"
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = Self.defaultRecordingName()
            NSApplication.shared.activate()

            guard panel.runModal() == .OK, let url = panel.url else {
                await self.recorder.cancelRecording(session: session)
                return
            }
            do {
                let written = try await self.recorder.endRecording(session: session, writingTo: url)
                self.recordedFrameCount = written
            } catch {
                self.lastError = "Could not save fixture: \(String(describing: error))"
            }
        }
    }

    private static func defaultRecordingName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "recording-\(formatter.string(from: Date())).json"
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
        case .neutral: return "neutral"
        case .pointing: return "pointing"
        case .pressed(.left): return "left button held"
        case .pressed(.right): return "right button held"
        case .scrolling: return "scrolling"
        case .palm: return "open palm"
        case .zooming: return "zooming"
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
