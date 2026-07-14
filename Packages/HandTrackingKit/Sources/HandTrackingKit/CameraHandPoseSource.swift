import AVFoundation
import CoreMedia
import HandPoseCore
import Vision

/// Live hand tracking: AVCaptureSession frames → synchronous Vision hand-pose
/// inference → `HandPoseFrame` stream.
///
/// Design constraints from the spec:
/// - 640×480 capture, 60 fps requested (clamped to what the camera supports),
///   `alwaysDiscardsLateVideoFrames` + synchronous inference on the serial
///   delegate queue for natural backpressure — frames drop rather than queue.
/// - Newest-only stream buffering: a slow consumer never sees a stale hand.
/// - A frame with no detected hand is still yielded (empty joints) so
///   downstream stages can notice hand loss promptly.
///
/// A source instance is single-use: `stop()` finishes the stream; create a
/// new instance to track again.
public final class CameraHandPoseSource: NSObject, HandPoseSource, @unchecked Sendable {
    // Concurrency: `session`/`configured` are confined to `sessionQueue`;
    // `handPoseRequest` is confined to `videoQueue` (serial delegate queue).
    // The continuation and configuration values are immutable and Sendable.

    /// Exposed for the debug overlay's preview layer only. Attach a preview
    /// layer to it; never reconfigure it from outside.
    public let captureSession = AVCaptureSession()

    private let stream: AsyncStream<HandPoseFrame>
    private let continuation: AsyncStream<HandPoseFrame>.Continuation
    private let sessionQueue = DispatchQueue(label: "AirCursor.CameraHandPoseSource.session")
    private let videoQueue = DispatchQueue(label: "AirCursor.CameraHandPoseSource.video")
    private let minimumJointConfidence: Float
    private let targetFrameRate: Double
    private let handPoseRequest: VNDetectHumanHandPoseRequest
    private let requestAuthorization: @Sendable () async -> Bool
    private var configured = false

    /// Explicit lifecycle, confined to `sessionQueue`. `stop()` is terminal
    /// for a source instance — once stopped, the session can never start.
    private enum Lifecycle {
        case idle, running, stopped
    }
    private var lifecycle: Lifecycle = .idle
    /// Test hook (sessionQueue-confined): how many times the capture session
    /// was actually told to start. A stop-before-start race must keep this 0.
    private(set) var sessionStartCount = 0

    public var frames: AsyncStream<HandPoseFrame> { stream }

    public convenience init(minimumJointConfidence: Float = 0.3, targetFrameRate: Double = 60) {
        self.init(
            minimumJointConfidence: minimumJointConfidence,
            targetFrameRate: targetFrameRate,
            requestAuthorization: { await CameraPermission.requestAccess() }
        )
    }

    /// The authorization step is injectable so the stop/start race is
    /// deterministically testable without a real camera prompt.
    init(
        minimumJointConfidence: Float,
        targetFrameRate: Double,
        requestAuthorization: @escaping @Sendable () async -> Bool
    ) {
        self.minimumJointConfidence = minimumJointConfidence
        self.targetFrameRate = targetFrameRate
        self.requestAuthorization = requestAuthorization
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        self.handPoseRequest = request
        (self.stream, self.continuation) = AsyncStream.makeStream(
            of: HandPoseFrame.self, bufferingPolicy: .bufferingNewest(1)
        )
        super.init()
    }

    public func start() async throws {
        guard await requestAuthorization() else {
            throw HandTrackingError.cameraPermissionDenied
        }
        // Tracking may have been turned off while we awaited authorization.
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                // stop() may have run while authorization was in flight; on a
                // serial queue its block ran first, so this sees .stopped.
                guard self.lifecycle == .idle else {
                    cont.resume(throwing: CancellationError())
                    return
                }
                do {
                    try self.configureIfNeeded()
                    self.captureSession.startRunning()
                    self.sessionStartCount += 1
                    self.lifecycle = .running
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func stop() {
        sessionQueue.async {
            let wasRunning = self.lifecycle == .running
            self.lifecycle = .stopped
            if wasRunning {
                self.captureSession.stopRunning()
            }
            self.continuation.finish()
        }
    }

    // MARK: - Session configuration (sessionQueue)

    private func configureIfNeeded() throws {
        guard !configured else { return }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .unspecified
        ) ?? AVCaptureDevice.default(for: .video) else {
            throw HandTrackingError.noCameraAvailable
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if captureSession.canSetSessionPreset(.vga640x480) {
            captureSession.sessionPreset = .vga640x480
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw HandTrackingError.captureConfigurationFailed("cannot add camera input")
        }
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard captureSession.canAddOutput(output) else {
            throw HandTrackingError.captureConfigurationFailed("cannot add video output")
        }
        captureSession.addOutput(output)

        try configureFrameRate(on: device)
        configured = true
    }

    /// Requests `targetFrameRate`, clamped to the active format's maximum
    /// (built-in cameras often top out at 30 fps).
    private func configureFrameRate(on device: AVCaptureDevice) throws {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard let maxSupported = ranges.map(\.maxFrameRate).max() else { return }
        let rate = min(targetFrameRate, maxSupported)
        guard rate > 0 else { return }

        let duration = CMTime(value: 1, timescale: CMTimeScale(rate.rounded()))
        do {
            try device.lockForConfiguration()
        } catch {
            throw HandTrackingError.captureConfigurationFailed(
                "cannot lock camera for frame-rate configuration"
            )
        }
        defer { device.unlockForConfiguration() }
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }
}

// MARK: - Per-frame inference (videoQueue)

extension CameraHandPoseSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = sampleBuffer.presentationTimeStamp.seconds

        // Synchronous perform: combined with alwaysDiscardsLateVideoFrames,
        // inference time longer than a frame interval drops frames instead of
        // queueing stale ones.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([handPoseRequest])
        } catch {
            return
        }

        let frame: HandPoseFrame
        if let observation = handPoseRequest.results?.first {
            frame = VisionConversion.frame(
                from: observation,
                timestamp: timestamp,
                minimumConfidence: minimumJointConfidence
            )
        } else {
            frame = HandPoseFrame(joints: [:], timestamp: timestamp)
        }
        continuation.yield(frame)
    }
}
