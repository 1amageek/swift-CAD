import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ChamferMode`.
extension CADIR.ChamferMode: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ChamferMode", caseName: rawValue, values: 0)
    }
}
