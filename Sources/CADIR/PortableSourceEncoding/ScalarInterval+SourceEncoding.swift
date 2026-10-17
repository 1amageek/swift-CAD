import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.ScalarInterval`.
extension CADGeometry.ScalarInterval: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.ScalarInterval", fields: 2, using: &admission)
        try encoder.field("lower", lower, using: &admission)
        try encoder.field("upper", upper, using: &admission)
    }
}
