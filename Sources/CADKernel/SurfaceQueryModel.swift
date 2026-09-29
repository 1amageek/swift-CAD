import CADCore
import CADIR
import CADModeling
import CADTopology

/// What surface queries read: a B-rep and how stable subshape references resolve in it. An
/// evaluated document answers them after evaluation, and an evaluation context during it, so a
/// feature can query the faces of the model it is evaluated in (Wrap's UVN charts).
public protocol SurfaceQueryModel: Sendable {
    var brep: BRepModel { get }
    func topologyReference(for reference: StableSubshapeReference) throws -> TopologyReference
}

extension EvaluatedDocument: SurfaceQueryModel {}

extension EvaluationContext: SurfaceQueryModel {
    public func topologyReference(for reference: StableSubshapeReference) throws -> TopologyReference {
        try StableSubshapeResolver().topologyReference(
            for: reference,
            model: brep,
            subshapes: subshapes,
            lineage: lineage,
            tolerance: tolerance
        )
    }
}
