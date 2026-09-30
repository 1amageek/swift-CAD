import CADCore
import CADIR

public struct PlanarRevolveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
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
        try context.tolerance.validate()
        guard case let .revolve(revolve) = feature.operation else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: context.tolerance,
                message: "PlanarRevolveFeatureEvaluator only supports revolve."
            )
        }
        guard revolve.operation == .newBody else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: context.tolerance,
                message: "PlanarRevolveFeatureEvaluator only supports newBody revolve."
            )
        }
        try revolve.validate(tolerance: context.tolerance)
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
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                residual: angle.isFinite ? abs(angle) : nil,
                tolerance: context.tolerance,
                message: "Revolve requires a finite nonzero angle."
            )
        }
        guard abs(angle) <= Double.pi * 2.0 + context.tolerance.angle else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                residual: abs(angle) - 2.0 * Double.pi,
                tolerance: context.tolerance,
                message: "Revolve angle must not exceed one full turn."
            )
        }

        let profile: Profile
        switch revolve.section {
        case .face:
            // Refused by the feature's validation; a face section is not read here.
            throw FeatureEvaluationError.invalidGraph("Revolve takes a profile or a curve section.")
        case .curve(let reference):
            let section = try ResolvedModelingSection.resolveCurve(reference,
                from: context.curves[reference.featureID], tolerance: context.tolerance)
            return try CurvedRevolveBodyBuilder.buildSheet(axis: revolve.axis, angle: angle,
                section: section, featureID: feature.id, context: context, sewer: sewer)
        case .profile(let reference):
            profile = try ResolvedModelingSection.resolveProfile(reference,
                from: context.profiles[reference.featureID])
        }

        // Multi-loop regions require one topology authority for cap holes,
        // detached void shells, pcurves, and volume ownership. The general
        // exact sewing path provides that contract even when every boundary is
        // linear; the analytic fast path remains specialized for one loop.
        let requiresGeneralTopology = revolve.resultKind == .sheet || profile.innerLoops.isEmpty == false
            || profile.boundaryLoops.flatMap(\.boundarySegments).contains(where: { segment in
            switch segment {
            case .line:
                return false
            case .circularArc, .spline:
                return true
            }
        })
        if requiresGeneralTopology {
            return try CurvedRevolveBodyBuilder(
                axis: revolve.axis,
                angle: angle,
                profile: profile,
                featureID: feature.id,
                context: context,
                sewer: sewer
            ).build(from: profile, resultKind: revolve.resultKind)
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
