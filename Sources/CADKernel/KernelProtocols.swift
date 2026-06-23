import CADCore
import CADIR

public protocol ParameterResolving: Sendable {
    func resolve(_ table: ParameterTable) throws -> ResolvedParameterTable
    func evaluate(
        _ expression: CADExpression,
        parameters: ResolvedParameterTable,
        variables: [String: Quantity]
    ) throws -> Quantity
}

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

public protocol FeatureEvaluating: Sendable {
    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult
}

public protocol BRepBooleanEvaluating: Sendable {
    func evaluate(
        operation: SweepBooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        generatedNames: [PersistentName: TopologyReference],
        toolGeneratedNames: [PersistentName: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult
}

public protocol Tessellating: Sendable {
    func tessellate(model: BRepModel, options: TessellationOptions) throws -> [BodyID: Mesh]
}

public struct EvaluationContext: Sendable {
    public var parameters: ResolvedParameterTable
    public var brep: BRepModel
    public var profiles: [FeatureID: [Profile]]
    public var curves: [FeatureID: [EvaluatedCurve]]
    public var generatedNames: [PersistentName: TopologyReference]
    public var tolerance: ModelingTolerance

    public init(
        parameters: ResolvedParameterTable,
        brep: BRepModel,
        profiles: [FeatureID: [Profile]],
        curves: [FeatureID: [EvaluatedCurve]] = [:],
        generatedNames: [PersistentName: TopologyReference] = [:],
        tolerance: ModelingTolerance
    ) {
        self.parameters = parameters
        self.brep = brep
        self.profiles = profiles
        self.curves = curves
        self.generatedNames = generatedNames
        self.tolerance = tolerance
    }
}

public struct EvaluationResult: Sendable {
    public var brep: BRepModel
    public var generatedNames: [PersistentName: TopologyReference]
    public var removedGeneratedNames: Set<PersistentName>
    public var generatedCurves: [EvaluatedCurve]

    public init(
        brep: BRepModel,
        generatedNames: [PersistentName: TopologyReference],
        removedGeneratedNames: Set<PersistentName> = [],
        generatedCurves: [EvaluatedCurve] = []
    ) {
        self.brep = brep
        self.generatedNames = generatedNames
        self.removedGeneratedNames = removedGeneratedNames
        self.generatedCurves = generatedCurves
    }
}

public struct EvaluatedDocument: Sendable {
    public var document: CADDocument
    public var parameters: ResolvedParameterTable
    public var brep: BRepModel
    public var meshes: [BodyID: Mesh]
    public var curves: [FeatureID: [EvaluatedCurve]]
    public var caches: DocumentCaches
    public var generatedNames: [PersistentName: TopologyReference]

    public init(
        document: CADDocument,
        parameters: ResolvedParameterTable,
        brep: BRepModel,
        meshes: [BodyID: Mesh],
        curves: [FeatureID: [EvaluatedCurve]] = [:],
        caches: DocumentCaches,
        generatedNames: [PersistentName: TopologyReference]
    ) {
        self.document = document
        self.parameters = parameters
        self.brep = brep
        self.meshes = meshes
        self.curves = curves
        self.caches = caches
        self.generatedNames = generatedNames
    }
}
