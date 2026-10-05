import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.SolidShellComponent`.
extension CADTopology.SolidShellComponent: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.SolidShellComponent", fields: 2)
        try encoder.field("outerShellID", outerShellID)
        try encoder.field("voidShellIDs", voidShellIDs)
    }
}
