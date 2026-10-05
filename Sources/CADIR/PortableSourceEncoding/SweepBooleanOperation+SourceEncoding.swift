import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepBooleanOperation`.
extension CADIR.SweepBooleanOperation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SweepBooleanOperation", caseName: rawValue, values: 0)
    }
}
