import CADCore
import CADGeometry

/// Retains the exact original physical-radian affine law and intrinsic tag.
extension CADGeometry.OriginalAngularParameterTransport: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .intrinsic:
            try encoder.enumeration("CADGeometry.OriginalAngularParameterTransport", caseName: "intrinsic", values: 0)
        case .physicalRadianArc(let start, let end, let additionalTurns):
            try encoder.enumeration("CADGeometry.OriginalAngularParameterTransport", caseName: "physicalRadianArc", values: 3)
            try encoder.field("additionalTurns", additionalTurns)
            try encoder.field("end", end)
            try encoder.field("start", start)
        case .physicalRadians(let gain, let offset):
            try encoder.enumeration("CADGeometry.OriginalAngularParameterTransport", caseName: "physicalRadians", values: 2)
            try encoder.field("gain", gain)
            try encoder.field("offset", offset)
        }
    }
}
