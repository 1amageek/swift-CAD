import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveOffsetSide`.
extension CADIR.CurveOffsetSide: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.CurveOffsetSide", caseName: rawValue, values: 0)
    }
}
