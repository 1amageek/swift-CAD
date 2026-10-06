import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapePositionFrame`.
extension CADIR.IndependentShapePositionFrame: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapePositionFrame", fields: 3)
        try encoder.field("frameID", frameID)
        try encoder.field("originalIGESAdjustments", originalIGESAdjustments)
        try encoder.field("parameterLengthUnit", parameterLengthUnit)
    }
}
