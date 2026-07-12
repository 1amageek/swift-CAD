import CADCore
import CADIR

public struct DocumentEvaluator: Sendable {
    private static let incrementalEvaluatorIdentity = "swift-cad.document-evaluator-dev"

    private let parameterResolver: ParameterResolving
    private let profileExtractor: SketchProfileExtracting
    private let curveExtractor: SketchCurveExtracting
    private let featureEvaluator: FeatureEvaluating
    private let tessellator: Tessellating
    private let tolerance: ModelingTolerance
    private let tessellationOptions: TessellationOptions
    private let artifactPolicy: EvaluationArtifactPolicy
    private let supportsIncrementalEvaluation: Bool

    public var evaluationTolerance: ModelingTolerance {
        tolerance
    }

    public init(
        parameterResolver: ParameterResolving = ParameterResolver(),
        profileExtractor: SketchProfileExtracting? = nil,
        curveExtractor: SketchCurveExtracting? = nil,
        featureEvaluator: FeatureEvaluating? = nil,
        tessellator: Tessellating? = nil,
        tolerance: ModelingTolerance = .standard,
        tessellationOptions: TessellationOptions = .standard,
        artifactPolicy: EvaluationArtifactPolicy = .materialized
    ) {
        self.parameterResolver = parameterResolver
        self.profileExtractor = profileExtractor ?? SketchProfileExtractor(
            resolver: parameterResolver,
            tolerance: tolerance
        )
        self.curveExtractor = curveExtractor ?? SketchCurveExtractor(
            resolver: parameterResolver,
            tolerance: tolerance
        )
        self.featureEvaluator = featureEvaluator ?? DefaultFeatureEvaluator(resolver: parameterResolver)
        self.tessellator = tessellator ?? MeshTessellator(tolerance: tolerance)
        self.tolerance = tolerance
        self.tessellationOptions = tessellationOptions
        self.artifactPolicy = artifactPolicy
        supportsIncrementalEvaluation = parameterResolver is ParameterResolver
            && profileExtractor == nil
            && curveExtractor == nil
            && featureEvaluator == nil
            && tessellator == nil
    }

    public func evaluate(
        _ document: CADDocument,
        reusing previous: EvaluatedDocument? = nil
    ) throws -> EvaluatedDocument {
        let validatedDocument = try ValidatedCADDocument(document, tolerance: tolerance)
        return try evaluate(validatedDocument, reusing: previous)
    }

    public func evaluate(
        _ document: ValidatedCADDocument,
        reusing previous: EvaluatedDocument? = nil
    ) throws -> EvaluatedDocument {
        try engine.evaluate(document, reusing: previous) { _, _ in }
    }

    public func evaluateReport(
        _ document: CADDocument,
        reusing previous: EvaluatedDocument? = nil
    ) -> EvaluationReport {
        do {
            let validatedDocument = try ValidatedCADDocument(document, tolerance: tolerance)
            return evaluateReport(validatedDocument, reusing: previous)
        } catch {
            return failedValidationReport(document: document, error: error)
        }
    }

    public func evaluateReport(
        _ validatedDocument: ValidatedCADDocument,
        reusing previous: EvaluatedDocument? = nil
    ) -> EvaluationReport {
        let document = validatedDocument.document
        var states: [FeatureID: FeatureEvaluationState] = [:]
        for featureID in document.designGraph.order {
            states[featureID] = .unevaluated
        }
        do {
            let evaluatedDocument = try engine.evaluate(validatedDocument, reusing: previous) { featureID, state in
                states[featureID] = state
            }
            for featureID in document.designGraph.order {
                guard case .some(.unevaluated) = states[featureID],
                      let feature = document.designGraph.nodes[featureID] else {
                    continue
                }
                states[featureID] = feature.isSuppressed ? .suppressed : .evaluated
            }
            return EvaluationReport(
                document: document,
                evaluatedDocument: evaluatedDocument,
                featureStates: states
            )
        } catch {
            let failure = EvaluationFailure(message: String(describing: error))
            return EvaluationReport(
                document: document,
                evaluatedDocument: nil,
                featureStates: states,
                failure: failure
            )
        }
    }

    func evaluateWithoutCacheValidation(_ document: CADDocument) throws -> EvaluatedDocument {
        let validatedDocument = try ValidatedCADDocument(document, tolerance: tolerance)
        return try engine.evaluate(validatedDocument, reusing: nil) { _, _ in }
    }

    private func failedValidationReport(document: CADDocument, error: Error) -> EvaluationReport {
        var states: [FeatureID: FeatureEvaluationState] = [:]
        states.reserveCapacity(document.designGraph.order.count)
        for featureID in document.designGraph.order {
            states[featureID] = .unevaluated
        }
        return EvaluationReport(
            document: document,
            evaluatedDocument: nil,
            featureStates: states,
            failure: EvaluationFailure(message: String(describing: error))
        )
    }

    private var engine: DocumentEvaluationEngine {
        DocumentEvaluationEngine(
            parameterResolver: parameterResolver,
            profileExtractor: profileExtractor,
            curveExtractor: curveExtractor,
            featureEvaluator: featureEvaluator,
            tessellator: tessellator,
            tolerance: tolerance,
            tessellationOptions: tessellationOptions,
            artifactPolicy: artifactPolicy,
            incrementalEvaluatorIdentity: supportsIncrementalEvaluation
                ? Self.incrementalEvaluatorIdentity
                : nil
        )
    }
}
