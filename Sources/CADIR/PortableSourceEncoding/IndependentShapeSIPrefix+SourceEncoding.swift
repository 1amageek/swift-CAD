import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeSIPrefix`.
extension CADIR.IndependentShapeSIPrefix: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.IndependentShapeSIPrefix", caseName: rawValue, values: 0)
    }
}
