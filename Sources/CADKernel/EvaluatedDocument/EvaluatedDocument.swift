import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public struct EvaluatedDocument: Sendable {
    public let document: CADDocument
    public let parameters: ResolvedParameterTable
    public let brep: BRepModel
    public let meshes: PersistentMap<BodyID, Mesh>
    public let curves: [FeatureID: [EvaluatedCurve]]
    public let caches: DocumentCaches
    public let subshapes: SubshapeIndex
    public let lineage: [SubshapeID: TopologyLineage]
    public let assembly: AssemblyEvaluationArtifact?
    public let configuration: DocumentEvaluationConfiguration
    public let evaluationMetrics: DocumentEvaluationMetrics
    var incrementalEvaluationState: IncrementalEvaluationState?
    var validatedBRep: ValidatedBRepModel?
    /// Producer-retained source authority for exact snapshots that intentionally omit caches.
    let validatedSourceReceipt: ValidatedCADDocument?

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
        assembly: AssemblyEvaluationArtifact? = nil,
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
        self.assembly = assembly
        self.evaluationMetrics = evaluationMetrics
        incrementalEvaluationState = nil
        validatedBRep = nil
        validatedSourceReceipt = nil
    }
}
