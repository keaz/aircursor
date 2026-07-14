import Foundation
import OnnxRuntimeBindings

enum OrtModelError: Error {
    case noInput
    case badOutput(String)
}

/// Thin wrapper over an ONNX Runtime session: loads a model once and runs it
/// on a single float32 input tensor, returning each output as a flat `[Float]`.
///
/// Confined to the capture queue by its owner; `@unchecked Sendable` because
/// `ORTSession` is not `Sendable` but is used single-threaded.
final class OrtModel: @unchecked Sendable {
    let inputNames: [String]
    let outputNames: [String]

    private let env: ORTEnv
    private let session: ORTSession

    init(modelPath: String) throws {
        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        inputNames = try session.inputNames()
        outputNames = try session.outputNames()
    }

    /// Runs the model on one float32 tensor of `shape` (row-major). Returns
    /// every output tensor as a flat float array keyed by name.
    func run(input: [Float], shape: [Int]) throws -> [String: [Float]] {
        guard let inputName = inputNames.first else { throw OrtModelError.noInput }

        let data = input.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress, length: $0.count) }
        let tensor = try ORTValue(
            tensorData: data,
            elementType: .float,
            shape: shape.map { NSNumber(value: $0) }
        )
        let outputs = try session.run(
            withInputs: [inputName: tensor],
            outputNames: Set(outputNames),
            runOptions: nil
        )

        var result: [String: [Float]] = [:]
        for (name, value) in outputs {
            let bytes = try value.tensorData() as Data
            result[name] = bytes.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self))
            }
        }
        return result
    }
}
