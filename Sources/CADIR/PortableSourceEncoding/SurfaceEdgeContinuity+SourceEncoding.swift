import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceEdgeContinuity`.
extension CADIR.SurfaceEdgeContinuity: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceEdgeContinuity", fields: 7)
        try encoder.field("angularAllowance", angularAllowance)
        try encoder.field("bodyRole", bodyRole)
        try encoder.field("curvatureAllowance", curvatureAllowance)
        try encoder.field("edge", edge)
        try encoder.field("order", order)
        try encoder.field("source", source)
        try encoder.field("tension", tension)
    }
}
