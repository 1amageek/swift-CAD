import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PolySplineOptions`.
extension CADIR.PolySplineOptions: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PolySplineOptions", fields: 3, using: &admission)
        try encoder.field("interpolateBoundaryExactly", interpolateBoundaryExactly, using: &admission)
        try encoder.field("mergePatches", mergePatches, using: &admission)
        try encoder.field("roundedCorners", roundedCorners, using: &admission)
    }
}
