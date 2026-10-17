import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeTrimmingSource.Preference`.
extension CADIR.IndependentShapeTrimmingSource.Preference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.IndependentShapeTrimmingSource.Preference", caseName: rawValue, values: 0, using: &admission)
    }
}
