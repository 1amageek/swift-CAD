import CADCore
import CADIR
import CADTopology

/// Validated B-rep and deterministic topology identity produced by sewing.
public struct BRepSewingResult: Sendable {
    public let brep: BRepModel
    public let bodyID: BodyID
    public let subshapes: [SubshapeID: TopologyReference]
    public let lineage: [SubshapeID: TopologyLineage]
    public let stableReferences: [BRepSewingStableKey: TopologyReference]

    public init(
        brep: BRepModel,
        bodyID: BodyID,
        subshapes: [SubshapeID: TopologyReference],
        lineage: [SubshapeID: TopologyLineage],
        stableReferences: [BRepSewingStableKey: TopologyReference]
    ) {
        self.brep = brep
        self.bodyID = bodyID
        self.subshapes = subshapes
        self.lineage = lineage
        self.stableReferences = stableReferences
    }
}
