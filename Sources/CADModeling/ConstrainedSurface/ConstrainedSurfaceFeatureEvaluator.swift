import CADCore
import CADGeometry
import CADIR
import Foundation

public struct ConstrainedSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let maximumMatrixElements: Int

    public init(maximumMatrixElements: Int = 1_000_000) {
        self.maximumMatrixElements = maximumMatrixElements
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        guard case .constrainedSurface(let source) = feature.operation, feature.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Constrained Surface requires point constraints without feature input ports.")
        }
        try source.validate(tolerance: context.tolerance)
        let builder = ConstrainedSurfaceHeightFitter(maximumMatrixElements: maximumMatrixElements)
        let surface = try builder.fit(source, tolerance: context.tolerance)
        var constructed = feature
        constructed.operation = .bSplineSurface(BSplineSurfaceFeature(surface: surface))
        return try BSplineSurfaceFeatureEvaluator().evaluateValidated(feature: constructed, context: context)
    }
}
