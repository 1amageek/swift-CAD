import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PolySplineOptions`.
extension CADIR.PolySplineOptions: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PolySplineOptions", fields: 3)
        try encoder.field("interpolateBoundaryExactly", interpolateBoundaryExactly)
        try encoder.field("mergePatches", mergePatches)
        try encoder.field("roundedCorners", roundedCorners)
    }
}
