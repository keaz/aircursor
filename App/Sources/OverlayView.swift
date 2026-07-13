import HandPoseCore
import SwiftUI

/// Development tool: camera preview with landmark dots, frame rate, and (from
/// M3) the gesture state and pinch metric.
struct OverlayView: View {
    let controller: AppController

    var body: some View {
        VStack(spacing: 12) {
            preview
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            hud
            recordingControls
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 400)
    }

    /// Records landmark fixtures (JSON, landmarks only — never video) for
    /// threshold tuning and engine tests.
    private var recordingControls: some View {
        HStack(spacing: 10) {
            Button {
                controller.toggleFixtureRecording()
            } label: {
                Label(
                    controller.isRecordingFixture ? "Stop & Save…" : "Record Fixture",
                    systemImage: controller.isRecordingFixture ? "stop.circle.fill" : "record.circle"
                )
            }
            .disabled(!controller.isTracking)

            if controller.isRecordingFixture || controller.recordedFrameCount > 0 {
                Text("\(controller.recordedFrameCount) frames")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(controller.isRecordingFixture ? .red : .secondary)
            }

            if controller.recordingReachedLimit {
                Text("length limit reached")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if controller.isTracking, let session = controller.captureSession {
            ZStack {
                CameraPreviewView(session: session)
                LandmarkDots(frame: controller.latestFrame)
            }
        } else {
            ContentUnavailableView(
                "Tracking is off",
                systemImage: "video.slash",
                description: Text("Start tracking from the AirCursor menu bar icon.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.5))
        }
    }

    private var hud: some View {
        HStack(spacing: 16) {
            Label(
                String(format: "%.0f fps", controller.framesPerSecond),
                systemImage: "speedometer"
            )
            .monospacedDigit()

            Label(
                handStatus,
                systemImage: handDetected ? "hand.raised.fill" : "hand.raised.slash"
            )

            Label(controller.gestureStateLabel, systemImage: "cursorarrow.motionlines")

            Label(pinchMetricText, systemImage: "arrow.down.left.and.arrow.up.right")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()
        }
        .font(.callout)
    }

    private var pinchMetricText: String {
        guard let metric = controller.indexPinchMetric else { return "pinch —" }
        return String(format: "pinch %.2f", metric)
    }

    private var handDetected: Bool {
        !(controller.latestFrame?.joints.isEmpty ?? true)
    }

    private var handStatus: String {
        guard let frame = controller.latestFrame, !frame.joints.isEmpty else {
            return "no hand"
        }
        return "\(frame.joints.count)/\(HandJoint.allCases.count) joints"
    }
}

/// Landmark dots in `HandPoseFrame` space, which matches the mirrored preview
/// directly: x right, y down, normalized to the 4:3 video rect.
private struct LandmarkDots: View {
    let frame: HandPoseFrame?

    var body: some View {
        Canvas { context, size in
            guard let frame else { return }
            for (joint, point) in frame.joints {
                let rect = CGRect(
                    x: point.x * size.width - 3,
                    y: point.y * size.height - 3,
                    width: 6,
                    height: 6
                )
                let isTip = [.thumbTip, .indexTip, .middleTip].contains(joint)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(isTip ? .orange : .green)
                )
            }
        }
        .allowsHitTesting(false)
    }
}
