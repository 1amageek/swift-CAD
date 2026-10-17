import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceFillFeature`.
extension CADIR.SurfaceFillFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceFillFeature", fields: 3, using: &admission)
        try encoder.field("boundarySeed", boundarySeed, using: &admission)
        try encoder.field("insertedSheet", insertedSheet, using: &admission)
        try encoder.field("targetFeatureID", targetFeatureID, using: &admission)
    }
}
