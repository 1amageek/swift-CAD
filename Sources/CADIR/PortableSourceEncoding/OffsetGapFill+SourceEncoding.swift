import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.OffsetGapFill`.
extension CADIR.OffsetGapFill: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.OffsetGapFill", caseName: rawValue, values: 0)
    }
}
