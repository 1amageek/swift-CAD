import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareRefit`.
extension CADIR.SquareRefit: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SquareRefit", fields: 5, using: &admission)
        try encoder.field("angularAllowance", angularAllowance, using: &admission)
        try encoder.field("curvatureAllowance", curvatureAllowance, using: &admission)
        try encoder.field("isFree", isFree, using: &admission)
        try encoder.field("options", options, using: &admission)
        try encoder.field("order", order, using: &admission)
    }
}
