import CADCore
import CADIR

public struct GridPatternFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
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
        guard case let .gridPattern(pattern) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Grid pattern evaluator requires a gridPattern feature."
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
        let firstSpacing = try resolvedSpacing(
            pattern.firstSpacing,
            operation: "gridPattern.firstSpacing",
            featureID: feature.id,
            context: context
        )
        let secondSpacing = try resolvedSpacing(
            pattern.secondSpacing,
            operation: "gridPattern.secondSpacing",
            featureID: feature.id,
            context: context
        )
        let firstDirection = try pattern.firstDirection.normalized(tolerance: context.tolerance.distance)
        let secondDirection = try pattern.secondDirection.normalized(tolerance: context.tolerance.distance)
        let directionCross = firstDirection.cross(secondDirection).length
        guard directionCross > context.tolerance.angle else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Grid pattern directions must be nonparallel at evaluation tolerance."
            )
        }
        let bodyID = try targetBodyID(pattern.target.featureID, featureID: feature.id, context: context)
        var transforms: [ExactPatternTransform] = []
        transforms.reserveCapacity(pattern.firstCount * pattern.secondCount)
        for secondIndex in 0..<pattern.secondCount {
            for firstIndex in 0..<pattern.firstCount {
                let offset = firstDirection * (firstSpacing * Double(firstIndex))
                    + secondDirection * (secondSpacing * Double(secondIndex))
                transforms.append(.translated(by: offset))
            }
        }
        return try rebuilder.rebuild(
            featureID: feature.id,
            sourceBodyID: bodyID,
            transforms: transforms,
            stablePrefix: "gridPattern",
            context: context
        )
    }

    private func resolvedSpacing(
        _ expression: CADExpression,
        operation: String,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: operation, expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw error(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Grid pattern spacing must be a positive length above modeling tolerance."
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
