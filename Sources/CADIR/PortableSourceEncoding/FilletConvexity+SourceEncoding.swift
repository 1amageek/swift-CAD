import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FilletConvexity`.
extension CADIR.FilletConvexity: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.FilletConvexity", caseName: rawValue, values: 0)
    }
}
