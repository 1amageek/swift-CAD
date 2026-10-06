import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepResultKind`.
extension CADIR.SweepResultKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SweepResultKind", caseName: rawValue, values: 0)
    }
}
