import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftFaceContinuity`.
extension CADIR.LoftFaceContinuity: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.LoftFaceContinuity", fields: 4, using: &admission)
        try encoder.field("angularAllowance", angularAllowance, using: &admission)
        try encoder.field("curvatureAllowance", curvatureAllowance, using: &admission)
        try encoder.field("order", order, using: &admission)
        try encoder.field("tension", tension, using: &admission)
    }
}
