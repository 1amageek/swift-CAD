import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpatialPathFeature.Kind`.
extension CADIR.SpatialPathFeature.Kind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SpatialPathFeature.Kind", caseName: rawValue, values: 0)
    }
}
