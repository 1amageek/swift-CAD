import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveExtensionEnd`.
extension CADIR.CurveExtensionEnd: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.CurveExtensionEnd", caseName: rawValue, values: 0)
    }
}
