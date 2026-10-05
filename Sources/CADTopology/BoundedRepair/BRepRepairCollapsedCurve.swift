import CADCore
import CADGeometry

/// Invocation-local original geometry retained after its topology edge is deleted.
struct BRepRepairCollapsedCurve: Sendable {
    let originalEdgeID: EdgeID
    let curve: Curve3D
    let interval: ScalarInterval
    var retainedVertexID: VertexID
}
