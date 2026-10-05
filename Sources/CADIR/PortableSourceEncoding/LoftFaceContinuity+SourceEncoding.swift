import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftFaceContinuity`.
extension CADIR.LoftFaceContinuity: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.LoftFaceContinuity", fields: 4)
        try encoder.field("angularAllowance", angularAllowance)
        try encoder.field("curvatureAllowance", curvatureAllowance)
        try encoder.field("order", order)
        try encoder.field("tension", tension)
    }
}
