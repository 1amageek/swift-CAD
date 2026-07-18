import CADCore
import CADIR
import CADTopology

/// The exact source state available to one feature evaluation.
public struct EvaluationContext: Sendable {
    public var parameters: ResolvedParameterTable
    public var brep: BRepModel
    public var profiles: [FeatureID: [Profile]]
    public var curves: [FeatureID: [EvaluatedCurve]]
    public var subshapes: SubshapeIndex
    public var lineage: [SubshapeID: TopologyLineage]
    public var tolerance: ModelingTolerance

    public init(
        parameters: ResolvedParameterTable,
        brep: BRepModel,
        profiles: [FeatureID: [Profile]],
        curves: [FeatureID: [EvaluatedCurve]] = [:],
        subshapes: SubshapeIndex = SubshapeIndex(),
        lineage: [SubshapeID: TopologyLineage] = [:],
        tolerance: ModelingTolerance
    ) {
        self.parameters = parameters
        self.brep = brep
        self.profiles = profiles
        self.curves = curves
        self.subshapes = subshapes
        self.lineage = lineage
        self.tolerance = tolerance
    }
}
