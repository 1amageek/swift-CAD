import CADCore
import CADGeometry

/// Retains the exact original physical-radian affine law and intrinsic tag.
extension CADGeometry.OriginalAngularParameterTransport: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .intrinsic:
            try encoder.enumeration("CADGeometry.OriginalAngularParameterTransport", caseName: "intrinsic", values: 0, using: &admission)
        case .physicalRadianArc(let start, let end, let additionalTurns):
            try encoder.enumeration("CADGeometry.OriginalAngularParameterTransport", caseName: "physicalRadianArc", values: 3, using: &admission)
            try encoder.field("additionalTurns", additionalTurns, using: &admission)
            try encoder.field("end", end, using: &admission)
            try encoder.field("start", start, using: &admission)
        case .physicalRadians(let gain, let offset):
            try encoder.enumeration("CADGeometry.OriginalAngularParameterTransport", caseName: "physicalRadians", values: 2, using: &admission)
            try encoder.field("gain", gain, using: &admission)
            try encoder.field("offset", offset, using: &admission)
        }
    }
}
