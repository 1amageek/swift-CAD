import CADCore
import CADIR

public struct PlanarExtrudeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: any BRepSewing

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver()
    ) {
        self.resolver = resolver
        self.sewer = sewer
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
        try context.tolerance.validate()
        guard case let .extrude(extrude) = feature.operation else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "PlanarExtrudeFeatureEvaluator only supports extrude."
            )
        }
        guard extrude.operation == .newBody else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "PlanarExtrudeFeatureEvaluator only supports newBody extrude."
            )
        }
        guard let profiles = context.profiles[extrude.profile.featureID],
              profiles.indices.contains(extrude.profile.profileIndex) else {
            throw FeatureEvaluationError.missingProfile(
                extrude.profile.featureID,
                extrude.profile.profileIndex
            )
        }
        let distance = try resolvedDistance(
            extrude.distance,
            context: context
        )
        let result = try ExactProfileExtrudeBodyBuilder(
            featureID: feature.id,
            context: context,
            sewer: sewer
        ).build(
            from: profiles[extrude.profile.profileIndex],
            direction: extrude.direction,
            distance: distance,
            bodyKind: .solid,
            includesCaps: true
        )
        return try ValidatedFeatureEvaluation(
            planarExtrusion: result,
            tolerance: context.tolerance
        )
    }

    package func evaluateSheet(
        from profile: Profile,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try ExactProfileExtrudeBodyBuilder(
            featureID: featureID,
            context: context,
            sewer: sewer
        ).build(
            from: profile,
            direction: direction,
            distance: distance,
            bodyKind: .sheet,
            includesCaps: false
        )
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(
            expression,
            parameters: context.parameters,
            variables: [:]
        )
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "extrude.distance",
                expected: .length,
                actual: quantity.kind
            )
        }
        guard quantity.value > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(quantity.value)
        }
        return quantity.value
    }
}
