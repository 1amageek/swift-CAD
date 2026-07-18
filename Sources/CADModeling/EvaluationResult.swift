import CADCore
import CADIR
import CADTopology

/// The exact B-rep, curve, identity, and lineage delta produced by one feature.
public struct EvaluationResult: Sendable {
    public var brep: BRepModel
    public var subshapes: [SubshapeID: TopologyReference]
    public var removedSubshapeIDs: Set<SubshapeID>
    public var generatedCurves: [EvaluatedCurve]
    public var lineage: [SubshapeID: TopologyLineage]

    public init(
        brep: BRepModel,
        subshapes: [SubshapeID: TopologyReference] = [:],
        removedSubshapeIDs: Set<SubshapeID> = [],
        generatedCurves: [EvaluatedCurve] = [],
        lineage: [SubshapeID: TopologyLineage] = [:]
    ) {
        self.brep = brep
        self.subshapes = subshapes
        self.removedSubshapeIDs = removedSubshapeIDs
        self.generatedCurves = generatedCurves
        self.lineage = lineage
    }
}
