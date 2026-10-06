import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ShellTargetReference`.
extension CADIR.ShellTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ShellTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
