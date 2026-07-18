import CADCore
import CADIR

public struct PlanarRevolveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
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
        let result = try evaluateUnvalidated(feature: feature, context: context)
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .revolve(revolve) = feature.operation else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "PlanarRevolveFeatureEvaluator only supports revolve."
            )
        }
        guard revolve.operation == .newBody else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "PlanarRevolveFeatureEvaluator only supports newBody revolve."
            )
        }
        try revolve.validate(tolerance: context.tolerance)
        guard let profiles = context.profiles[revolve.profile.featureID],
              profiles.indices.contains(revolve.profile.profileIndex) else {
            throw FeatureEvaluationError.missingProfile(
                revolve.profile.featureID,
                revolve.profile.profileIndex
            )
        }
        let resolvedAngle = try resolver.evaluate(
            revolve.angle,
            parameters: context.parameters,
            variables: [:]
        )
        guard resolvedAngle.kind == .angle else {
            throw UnitError.expectedQuantity(
                operation: "revolve.angle",
                expected: .angle,
                actual: resolvedAngle.kind
            )
        }
        let angle = resolvedAngle.value
        guard angle.isFinite, abs(angle) > context.tolerance.angle else {
            throw FeatureEvaluationError.invalidDistance(angle)
        }
        guard abs(angle) <= Double.pi * 2.0 + context.tolerance.angle else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "Revolve angle must not exceed one full turn."
            )
        }

        let profile = profiles[revolve.profile.profileIndex]
        if profile.boundarySegments.contains(where: { segment in
            switch segment {
            case .line:
                return false
            case .circularArc, .spline:
                return true
            }
        }) {
            return try CurvedRevolveBodyBuilder(
                axis: revolve.axis,
                angle: angle,
                profile: profile,
                featureID: feature.id,
                context: context
            ).build(from: profile)
        }
        return try RevolveBodyBuilder(
            axis: revolve.axis,
            angle: angle,
            profile: profile,
            featureID: feature.id,
            context: context
        ).build(from: profile)
    }
}
