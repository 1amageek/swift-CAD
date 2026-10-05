import CADCore
import CADIR
import CADModeling
import CADTopology

extension EvaluatedDocument {
    /// Derives immutable source authority from the original validation receipt.
    /// No independent document argument can be substituted while retaining it.
    init(validatedSourceReceipt: ValidatedCADDocument,
         parameters: ResolvedParameterTable, brep: BRepModel,
         meshes: PersistentMap<BodyID, Mesh>, curves: [FeatureID: [EvaluatedCurve]],
         caches: DocumentCaches, subshapes: SubshapeIndex,
         lineage: [SubshapeID: TopologyLineage], configuration: DocumentEvaluationConfiguration,
         assembly: AssemblyEvaluationArtifact?, evaluationMetrics: DocumentEvaluationMetrics) throws {
        guard validatedSourceReceipt.tolerance == configuration.tolerance else {
            throw KernelError(phase: .evaluation, code: .invalidInput,
                tolerance: configuration.tolerance,
                message: "Original source receipt tolerance does not match the evaluation configuration.")
        }
        self.document = validatedSourceReceipt.document
        self.validatedSourceReceipt = validatedSourceReceipt
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
        self.incrementalEvaluationState = nil
        self.validatedBRep = nil
    }

    /// Preserves producer binding while replacing independently validated cache artifacts.
    func replacingCaches(_ caches: DocumentCaches) throws -> Self {
        var result: Self
        if let receipt = validatedSourceReceipt {
            result = try Self(validatedSourceReceipt: receipt, parameters: parameters,
                brep: brep, meshes: meshes, curves: curves, caches: caches,
                subshapes: subshapes, lineage: lineage, configuration: configuration,
                assembly: assembly, evaluationMetrics: evaluationMetrics)
        } else {
            result = Self(document: document, parameters: parameters, brep: brep,
                meshes: meshes, curves: curves, caches: caches, subshapes: subshapes,
                lineage: lineage, configuration: configuration, assembly: assembly,
                evaluationMetrics: evaluationMetrics)
        }
        result.incrementalEvaluationState = incrementalEvaluationState
        result.validatedBRep = validatedBRep
        return result
    }
}
