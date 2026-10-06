import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareRefit`.
extension CADIR.SquareRefit: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SquareRefit", fields: 5)
        try encoder.field("angularAllowance", angularAllowance)
        try encoder.field("curvatureAllowance", curvatureAllowance)
        try encoder.field("isFree", isFree)
        try encoder.field("options", options)
        try encoder.field("order", order)
    }
}
