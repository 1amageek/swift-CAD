import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeTrimmingSource.Preference`.
extension CADIR.IndependentShapeTrimmingSource.Preference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.IndependentShapeTrimmingSource.Preference", caseName: rawValue, values: 0)
    }
}
