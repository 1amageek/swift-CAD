import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ShellFeature`.
extension CADIR.ShellFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ShellFeature", fields: 3)
        try encoder.field("removedFaces", removedFaces)
        try encoder.field("target", target)
        try encoder.field("thickness", thickness)
    }
}
