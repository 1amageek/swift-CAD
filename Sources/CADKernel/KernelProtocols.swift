import CADCore
import CADIR
import CADModeling
import CADTopology

public protocol SketchProfileExtracting: Sendable {
    func extractProfiles(
        from sketch: Sketch,
        sourceFeatureID: FeatureID,
        parameters: ResolvedParameterTable
    ) throws -> [Profile]
}

public protocol SketchCurveExtracting: Sendable {
    func extractCurves(
        from sketch: Sketch,
        sourceFeatureID: FeatureID,
        parameters: ResolvedParameterTable
    ) throws -> [EvaluatedCurve]
}

public protocol BRepBooleanEvaluating: Sendable {
    func intersectionRequirement(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionRequirement

    func exactRegionSelection(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        tolerance: ModelingTolerance
    ) throws -> BooleanExactRegionSelectionGraph

    func evaluate(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        intersectionGraph: BooleanIntersectionGraph,
        uvSplitGraph: BooleanUVSplitGraph,
        classificationGraph: BooleanClassificationGraph,
        exactRegionSelectionGraph: BooleanExactRegionSelectionGraph,
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult
}

public extension BRepBooleanEvaluating {
    func intersectionRequirement(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionRequirement {
        .required
    }
}

public protocol Tessellating: Sendable {
    func tessellate(model: BRepModel, options: TessellationOptions) throws -> [BodyID: Mesh]
    func tessellate(
        validatedModel: ValidatedBRepModel,
        options: TessellationOptions
    ) throws -> [BodyID: Mesh]
}

public extension Tessellating {
    func tessellate(
        validatedModel: ValidatedBRepModel,
        options: TessellationOptions
    ) throws -> [BodyID: Mesh] {
        try tessellate(model: validatedModel.model, options: options)
    }
}

public struct EvaluatedDocument: Sendable {
    public let document: CADDocument
    public let parameters: ResolvedParameterTable
    public let brep: BRepModel
    public let meshes: PersistentMap<BodyID, Mesh>
    public let curves: [FeatureID: [EvaluatedCurve]]
    public let caches: DocumentCaches
    public let subshapes: SubshapeIndex
    public let lineage: [SubshapeID: TopologyLineage]
    public let configuration: DocumentEvaluationConfiguration
    public let evaluationMetrics: DocumentEvaluationMetrics
    var incrementalEvaluationState: IncrementalEvaluationState?

    public init(
        document: CADDocument,
        parameters: ResolvedParameterTable,
        brep: BRepModel,
        meshes: PersistentMap<BodyID, Mesh>,
        curves: [FeatureID: [EvaluatedCurve]] = [:],
        caches: DocumentCaches,
        subshapes: SubshapeIndex = SubshapeIndex(),
        lineage: [SubshapeID: TopologyLineage] = [:],
        configuration: DocumentEvaluationConfiguration,
        evaluationMetrics: DocumentEvaluationMetrics = DocumentEvaluationMetrics()
    ) {
        self.document = document
        self.parameters = parameters
        self.brep = brep
        self.meshes = meshes
        self.curves = curves
        self.caches = caches
        self.subshapes = subshapes
        self.lineage = lineage
        self.configuration = configuration
        self.evaluationMetrics = evaluationMetrics
        incrementalEvaluationState = nil
    }
}
