import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CylinderPrimitive`.
extension CADIR.CylinderPrimitive: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CylinderPrimitive", fields: 3, using: &admission)
        try encoder.field("height", height, using: &admission)
        try encoder.field("placement", placement, using: &admission)
        try encoder.field("radius", radius, using: &admission)
    }
}
