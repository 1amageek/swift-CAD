import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CylinderPrimitive`.
extension CADIR.CylinderPrimitive: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CylinderPrimitive", fields: 3)
        try encoder.field("height", height)
        try encoder.field("placement", placement)
        try encoder.field("radius", radius)
    }
}
