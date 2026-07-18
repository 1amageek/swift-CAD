import CADCore
import CADIR
import CADTopology

struct BoundaryEdgeSplit {
    var originalEdgeID: EdgeID
    var originalCurveID: CurveID
    var splitVertexID: VertexID
    var firstEdgeID: EdgeID
    var secondEdgeID: EdgeID
    var splitFraction: Double
    var subshapes: [SubshapeID: TopologyReference]
    var lineage: [SubshapeID: TopologyLineage]
}
