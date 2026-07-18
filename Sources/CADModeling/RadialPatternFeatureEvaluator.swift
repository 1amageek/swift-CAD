import CADCore
import CADIR

public struct RadialPatternFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let rebuilder: any ExactPlanarPatternRebuilding

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        sewer: any BRepSewing = DefaultBRepSewer()
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
        guard case let .radialPattern(pattern) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Radial pattern evaluator requires a radialPattern feature."
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
        let angularSpacing = try resolvedAngularSpacing(
            pattern.angularSpacing,
            featureID: feature.id,
            context: context
        )
        let bodyID = try targetBodyID(pattern.target.featureID, featureID: feature.id, context: context)
        let transforms = try (0..<pattern.count).map { index in
            try ExactPatternTransform.rotated(
                around: pattern.axisOrigin,
                direction: pattern.axisDirection,
                angle: angularSpacing * Double(index),
                tolerance: context.tolerance
            )
        }
        return try rebuilder.rebuild(
            featureID: feature.id,
            sourceBodyID: bodyID,
            transforms: transforms,
            stablePrefix: "radialPattern",
            context: context
        )
    }

    private func resolvedAngularSpacing(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .angle else {
            throw UnitError.expectedQuantity(
                operation: "radialPattern.angularSpacing",
                expected: .angle,
                actual: quantity.kind
            )
        }
        guard quantity.value.isFinite,
              abs(quantity.value) > context.tolerance.angle else {
            throw error(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Radial pattern angular spacing must be a finite nonzero angle above modeling tolerance."
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
