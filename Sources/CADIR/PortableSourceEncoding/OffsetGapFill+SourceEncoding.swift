import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.OffsetGapFill`.
extension CADIR.OffsetGapFill: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.OffsetGapFill", caseName: rawValue, values: 0, using: &admission)
    }
}
