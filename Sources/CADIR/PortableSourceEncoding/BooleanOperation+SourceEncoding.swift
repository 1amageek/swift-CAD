import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanOperation`.
extension CADIR.BooleanOperation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.BooleanOperation", caseName: rawValue, values: 0, using: &admission)
    }
}
