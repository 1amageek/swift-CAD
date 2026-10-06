import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepCornerStyle`.
extension CADIR.SweepCornerStyle: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SweepCornerStyle", caseName: rawValue, values: 0)
    }
}
