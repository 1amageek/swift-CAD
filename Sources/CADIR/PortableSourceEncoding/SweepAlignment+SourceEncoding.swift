import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepAlignment`.
extension CADIR.SweepAlignment: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SweepAlignment", caseName: rawValue, values: 0)
    }
}
