import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ShellFeature`.
extension CADIR.ShellFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ShellFeature", fields: 3, using: &admission)
        try encoder.field("removedFaces", removedFaces, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("thickness", thickness, using: &admission)
    }
}
