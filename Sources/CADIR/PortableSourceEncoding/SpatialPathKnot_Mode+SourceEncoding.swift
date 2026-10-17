import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpatialPathKnot.Mode`.
extension CADIR.SpatialPathKnot.Mode: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SpatialPathKnot.Mode", caseName: rawValue, values: 0, using: &admission)
    }
}
