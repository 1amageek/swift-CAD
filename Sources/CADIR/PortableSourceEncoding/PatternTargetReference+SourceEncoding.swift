import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PatternTargetReference`.
extension CADIR.PatternTargetReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PatternTargetReference", fields: 1, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
    }
}
