import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanMaterial`.
extension CADIR.BooleanMaterial: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.BooleanMaterial", caseName: rawValue, values: 0)
    }
}
