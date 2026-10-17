import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpatialPathFeature.Kind`.
extension CADIR.SpatialPathFeature.Kind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SpatialPathFeature.Kind", caseName: rawValue, values: 0, using: &admission)
    }
}
