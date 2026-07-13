import AVFoundation
import CoreMedia
import Foundation
import HandPoseCore
import HandTrackingKit
import Vision

// Offline dev tool: runs Vision hand-pose detection over a gesture video and
// writes a landmark fixture JSON. Only derived landmarks are ever written —
// video frames stay in the input file.
//
// Usage:
//   fixture-extract <input.mov> <output.json> [--already-mirrored]
//
// By default the input is treated like the live camera feed (unmirrored), so
// both axes flip into hand space. Pass --already-mirrored for videos captured
// with a mirrored (selfie-style) preview, where only the y axis flips.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else {
    fail("usage: fixture-extract <input.mov> <output.json> [--already-mirrored]")
}
let inputURL = URL(fileURLWithPath: Array(arguments)[0])
let outputURL = URL(fileURLWithPath: Array(arguments)[1])
let alreadyMirrored = arguments.contains("--already-mirrored")

let asset = AVURLAsset(url: inputURL)
guard let track = try await asset.loadTracks(withMediaType: .video).first else {
    fail("no video track in \(inputURL.path)")
}

let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(
    track: track,
    outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]
)
reader.add(output)
guard reader.startReading() else {
    fail("cannot read \(inputURL.path): \(String(describing: reader.error))")
}

let request = VNDetectHumanHandPoseRequest()
request.maximumHandCount = 1

var frames: [HandPoseFrame] = []
var detected = 0

while let sampleBuffer = output.copyNextSampleBuffer() {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
    let timestamp = sampleBuffer.presentationTimeStamp.seconds

    try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        .perform([request])

    var frame: HandPoseFrame
    if let observation = request.results?.first {
        frame = VisionConversion.frame(
            from: observation, timestamp: timestamp, minimumConfidence: 0.3
        )
        if alreadyMirrored {
            // VisionConversion flipped x for an unmirrored feed; undo that
            // flip when the video was recorded through a mirrored preview.
            frame = HandPoseFrame(
                joints: frame.joints.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) },
                timestamp: timestamp
            )
        }
    } else {
        frame = HandPoseFrame(joints: [:], timestamp: timestamp)
    }
    if !frame.joints.isEmpty {
        detected += 1
    }
    frames.append(frame)
}

if reader.status == .failed {
    fail("reader failed: \(String(describing: reader.error))")
}
guard !frames.isEmpty else {
    fail("no frames decoded from \(inputURL.path)")
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(HandPoseFixture(frames: frames))
try data.write(to: outputURL, options: .atomic)

print("\(outputURL.lastPathComponent): \(frames.count) frames, hand detected in \(detected) (\(frames.isEmpty ? 0 : detected * 100 / frames.count)%)")
