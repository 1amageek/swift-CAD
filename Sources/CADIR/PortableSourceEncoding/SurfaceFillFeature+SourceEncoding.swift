import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceFillFeature`.
extension CADIR.SurfaceFillFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceFillFeature", fields: 3)
        try encoder.field("boundarySeed", boundarySeed)
        try encoder.field("insertedSheet", insertedSheet)
        try encoder.field("targetFeatureID", targetFeatureID)
    }
}
