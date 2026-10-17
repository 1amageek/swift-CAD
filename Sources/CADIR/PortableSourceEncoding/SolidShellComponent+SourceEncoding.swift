import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.SolidShellComponent`.
extension CADTopology.SolidShellComponent: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.SolidShellComponent", fields: 2, using: &admission)
        try encoder.field("outerShellID", outerShellID, using: &admission)
        try encoder.field("voidShellIDs", voidShellIDs, using: &admission)
    }
}
