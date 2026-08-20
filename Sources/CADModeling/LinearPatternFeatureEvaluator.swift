import CADCore
import CADIR

public struct LinearPatternFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let rebuilder: any ExactPlanarPatternRebuilding

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver()
    ) {
        self.resolver = resolver
        self.rebuilder = DefaultExactPlanarPatternRebuilder(sewer: sewer)
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .linearPattern(pattern) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Linear pattern evaluator requires a linearPattern feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try pattern.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let spacing = try resolvedSpacing(pattern.spacing, featureID: feature.id, context: context)
        let direction = try pattern.direction.normalized(tolerance: context.tolerance.distance)
        let bodyID = try targetBodyID(pattern.target.featureID, featureID: feature.id, context: context)
        let transforms = (0..<pattern.count).map { index in
            ExactPatternTransform.translated(by: direction * (spacing * Double(index)))
        }
        return try rebuilder.rebuild(
            featureID: feature.id,
            sourceBodyID: bodyID,
            transforms: transforms,
            stablePrefix: "linearPattern",
            context: context
        )
    }

    private func resolvedSpacing(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: "linearPattern.spacing", expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw error(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Linear pattern spacing must be a positive length above modeling tolerance."
            )
        }
        return quantity.value
    }

    private func targetBodyID(
        _ sourceFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: sourceFeatureID)
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
