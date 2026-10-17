import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SolidOperation`.
extension CADIR.SolidOperation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SolidOperation", caseName: rawValue, values: 0, using: &admission)
    }
}
