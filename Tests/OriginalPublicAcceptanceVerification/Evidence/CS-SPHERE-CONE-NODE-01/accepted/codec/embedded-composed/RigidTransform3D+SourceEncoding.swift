import CADCore

/// Encodes original source fields owned by `CADGeometry.RigidTransform3D`.
extension CADGeometry.RigidTransform3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.RigidTransform3D", fields: 4)
        try encoder.field("basisX", basisX)
        try encoder.field("basisY", basisY)
        try encoder.field("basisZ", basisZ)
        try encoder.field("translation", translation)
    }
}
