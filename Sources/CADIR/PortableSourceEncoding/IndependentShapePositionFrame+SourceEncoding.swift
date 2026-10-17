import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapePositionFrame`.
extension CADIR.IndependentShapePositionFrame: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapePositionFrame", fields: 3, using: &admission)
        try encoder.field("frameID", frameID, using: &admission)
        try encoder.field("originalIGESAdjustments", originalIGESAdjustments, using: &admission)
        try encoder.field("parameterLengthUnit", parameterLengthUnit, using: &admission)
    }
}
