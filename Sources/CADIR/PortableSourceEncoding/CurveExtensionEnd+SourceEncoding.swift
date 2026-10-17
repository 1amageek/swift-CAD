import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveExtensionEnd`.
extension CADIR.CurveExtensionEnd: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.CurveExtensionEnd", caseName: rawValue, values: 0, using: &admission)
    }
}
