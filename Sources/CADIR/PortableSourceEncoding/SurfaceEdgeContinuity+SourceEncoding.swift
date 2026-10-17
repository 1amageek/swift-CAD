import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceEdgeContinuity`.
extension CADIR.SurfaceEdgeContinuity: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceEdgeContinuity", fields: 7, using: &admission)
        try encoder.field("angularAllowance", angularAllowance, using: &admission)
        try encoder.field("bodyRole", bodyRole, using: &admission)
        try encoder.field("curvatureAllowance", curvatureAllowance, using: &admission)
        try encoder.field("edge", edge, using: &admission)
        try encoder.field("order", order, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("tension", tension, using: &admission)
    }
}
