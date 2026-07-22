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

public struct EvaluatedDocument: Codable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case document
        case parameters
        case brep
        case meshes
        case curves
        case caches
        case subshapes
        case lineage
        case configuration
        case evaluationMetrics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .document,
                .parameters,
                .brep,
                .meshes,
                .curves,
                .caches,
                .subshapes,
                .lineage,
                .configuration,
                .evaluationMetrics,
            ],
            in: decoder
        )
        let decoded = EvaluatedDocument(
            document: try container.decode(CADDocument.self, forKey: .document),
            parameters: try container.decode(ResolvedParameterTable.self, forKey: .parameters),
            brep: try container.decode(BRepModel.self, forKey: .brep),
            meshes: try container.decode(PersistentMap<BodyID, Mesh>.self, forKey: .meshes),
            curves: try container.decode([FeatureID: [EvaluatedCurve]].self, forKey: .curves),
            caches: try container.decode(DocumentCaches.self, forKey: .caches),
            subshapes: try container.decode(SubshapeIndex.self, forKey: .subshapes),
            lineage: try container.decode([SubshapeID: TopologyLineage].self, forKey: .lineage),
            configuration: try container.decode(
                DocumentEvaluationConfiguration.self,
                forKey: .configuration
            ),
            evaluationMetrics: try container.decode(
                DocumentEvaluationMetrics.self,
                forKey: .evaluationMetrics
            )
        )
        try decoded.validate()
        self = decoded
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(document, forKey: .document)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(brep, forKey: .brep)
        try container.encode(meshes, forKey: .meshes)
        try container.encode(curves, forKey: .curves)
        try container.encode(caches, forKey: .caches)
        try container.encode(subshapes, forKey: .subshapes)
        try container.encode(lineage, forKey: .lineage)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(evaluationMetrics, forKey: .evaluationMetrics)
    }
}
