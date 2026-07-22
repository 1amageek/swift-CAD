import CADCore
import CADIR
import CADTopology

struct BRepSewingDraft: Sendable {
    let brep: BRepModel
    let bodyID: BodyID
    let subshapes: [SubshapeID: TopologyReference]
    let lineage: [SubshapeID: TopologyLineage]
    let stableReferences: [BRepSewingStableKey: TopologyReference]
}
