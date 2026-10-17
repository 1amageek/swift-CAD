import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.RigidTransform3D`.
extension CADGeometry.RigidTransform3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.RigidTransform3D", fields: 4, using: &admission)
        try encoder.field("basisX", basisX, using: &admission)
        try encoder.field("basisY", basisY, using: &admission)
        try encoder.field("basisZ", basisZ, using: &admission)
        try encoder.field("translation", translation, using: &admission)
    }
}
