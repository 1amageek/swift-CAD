#if !hasFeature(Embedded)
import CADCore
import Foundation

enum CoreNativeCodecProof {
    static func run() throws {
        try wire(Point2D(x: 1.25, y: -2.5), literal: #"{"x":1.25,"y":-2.5}"#)
        try wire(Point3D(x: 1.25, y: -2.5, z: 3.75), literal: #"{"x":1.25,"y":-2.5,"z":3.75}"#)
        try wire(Vector3D(x: 1.25, y: -2.5, z: 3.75), literal: #"{"x":1.25,"y":-2.5,"z":3.75}"#)
        try wire(Matrix4x4.identity, literal: "[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]")
        try wire(Transform3D.identity, literal: #"{"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}"#)
        try wire(SchemaVersion(major: 2, minor: 3, patch: 4), literal: #"{"major":2,"minor":3,"patch":4}"#)
        try wire(CADExpression.hypot(.constant(.scalar(3)), .constant(.scalar(4))), literal:
            #"{"kind":"hypot","left":{"kind":"constant","quantity":{"value":3,"kind":"scalar"}},"right":{"kind":"constant","quantity":{"value":4,"kind":"scalar"}}}"#)
        try wire(BezierExtensionShape.reflective(degree: 3, coversCurve: true), literal:
            #"{"kind":"reflective","degree":3,"coversCurve":true}"#)
        do {
            _ = try JSONDecoder().decode(Matrix4x4.self, from: Data("[1,2,3]".utf8))
            throw CorePortabilityProofFailure.expectedFailure("matrix decode")
        } catch GeometryError.invalidMatrixElementCount(3) {}
        do {
            _ = try JSONDecoder().decode(CADExpression.self, from: Data(
                #"{"kind":"constant","quantity":{"value":1,"kind":"scalar"},"extra":true}"#.utf8))
            throw CorePortabilityProofFailure.expectedFailure("strict expression decode")
        } catch DecodingError.dataCorrupted(let context) {
            let normalized = KernelError.wrapping(
                DecodingError.dataCorrupted(context), phase: .validation, tolerance: .standard)
            guard context.codingPath.last?.stringValue == "extra", normalized.code == .invalidInput else {
                throw CorePortabilityProofFailure.unexpectedValue("codec error classification")
            }
        }
        do {
            _ = try JSONEncoder().encode(Point3D(x: .nan, y: 0, z: 0))
            throw CorePortabilityProofFailure.expectedFailure("nonfinite codec refusal")
        } catch EncodingError.invalidValue(let value, let context) {
            let normalized = KernelError.wrapping(
                EncodingError.invalidValue(value, context), phase: .validation, tolerance: .standard)
            guard normalized.code == .invalidInput else {
                throw CorePortabilityProofFailure.unexpectedValue("encoding error classification")
            }
        }
    }

    private static func wire<Value: Codable & Equatable>(_ value: Value, literal: String) throws {
        let expected = Data(literal.utf8)
        let encoded = try JSONEncoder().encode(value)
        guard try normalized(encoded) == normalized(expected),
              try JSONDecoder().decode(Value.self, from: expected) == value else {
            throw CorePortabilityProofFailure.unexpectedValue("native literal wire")
        }
    }

    private static func normalized(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }
}
#endif
