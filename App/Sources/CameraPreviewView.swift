import AVFoundation
import SwiftUI

/// AVCaptureVideoPreviewLayer wrapper, mirrored horizontally so the preview
/// matches `HandPoseFrame` space (hand moves right → image moves right).
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        PreviewNSView(session: session)
    }

    func updateNSView(_ view: PreviewNSView, context: Context) {
        view.attach(session: session)
    }
}

final class PreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        attach(session: session)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func attach(session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        applyMirroring()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
        // The connection appears only once the session is configured, which
        // happens asynchronously after start — re-apply opportunistically.
        applyMirroring()
    }

    private func applyMirroring() {
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported,
              !connection.isVideoMirrored
        else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
