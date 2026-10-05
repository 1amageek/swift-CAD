import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PatternTargetReference`.
extension CADIR.PatternTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PatternTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
