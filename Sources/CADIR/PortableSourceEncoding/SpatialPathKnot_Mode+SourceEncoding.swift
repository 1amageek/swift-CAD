import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpatialPathKnot.Mode`.
extension CADIR.SpatialPathKnot.Mode: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SpatialPathKnot.Mode", caseName: rawValue, values: 0)
    }
}
