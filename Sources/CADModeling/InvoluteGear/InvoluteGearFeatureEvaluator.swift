import CADCore
import CADGeometry
import CADIR

public struct InvoluteGearFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: any ParameterResolving
    private let builder: any InvoluteGearProfileBuilding
    private let sweep: any FeatureEvaluating

    public init(sweep: any FeatureEvaluating,
        resolver: any ParameterResolving = ParameterResolver(),
        builder: any InvoluteGearProfileBuilding = InvoluteGearProfileBuilder()) {
        self.sweep = sweep
        self.resolver = resolver
        self.builder = builder
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        do {
            guard case let .involuteGear(gear) = feature.operation else {
                throw FeatureEvaluationError.invalidGraph("Gear evaluation requires native gear source.")
            }
            try gear.validate(tolerance: context.tolerance)
            let dimensions = try gear.resolvedDimensions {
                try resolver.evaluate($0, parameters: context.parameters, variables: [:])
            }
            func value(_ dimension: InvoluteGearFeature.Dimension) throws -> Double {
                guard let result = dimensions[dimension] else {
                    throw FeatureEvaluationError.invalidGraph("Resolved gear dimension is missing.")
                }
                return result
            }
            let profile = try builder.profile(sourceFeatureID: feature.id, toothCount: gear.toothCount,
                baseRadius: value(.baseRadius), pitchRadius: value(.pitchRadius),
                tipRadius: value(.tipRadius), rootRadius: value(.rootRadius),
                pitchToothAngle: value(.pitchToothAngle), filletRadius: value(.filletRadius),
                maximumError: value(.profileError), maximumSegments: gear.maximumSegments,
                tolerance: context.tolerance, origin: gear.origin)
            let width = try value(.width)
            let twist = try value(.twistAngle)
            let allowance = try value(.sweepError)
            let path = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [gear.origin, gear.origin + Vector3D(x: 0, y: 0, z: width)])
            var inputs = context
            inputs.profiles[feature.id] = [profile]
            inputs.curves[feature.id] = [EvaluatedCurve(sourceFeatureID: feature.id,
                source: .generatedFeature, kind: .spline, points: path.controlPoints,
                plane: nil, exactCurve: .bSpline(path), exactParameterDomain: path.domain)]
            let zero = CADExpression.constant(.angle(0, unit: .radian))
            let twistExpression = CADExpression.constant(.angle(twist, unit: .radian))
            let law: [SweepTwistKnot]? = gear.doubleHelical && twist != 0 ? [
                .init(position: 0, angle: zero),
                .init(position: 0.5, angle: twistExpression),
                .init(position: 1, angle: zero)
            ] : nil
            var operation = feature
            operation.operation = .sweep(SweepFeature(
                sections: [.profile(.init(featureID: feature.id))],
                path: .init(featureID: feature.id), options: .init(
                    twistAngle: gear.doubleHelical ? zero : twistExpression,
                    approximationTolerance: twist == 0 ? nil : .constant(.length(allowance, unit: .meter)),
                    twistLaw: law)))
            if let validatedSweep = sweep as? any ValidatedFeatureEvaluating {
                return try validatedSweep.evaluateValidated(feature: operation, context: inputs)
            }
            return try ValidatedFeatureEvaluation(
                validating: sweep.evaluate(feature: operation, context: inputs),
                tolerance: context.tolerance)
        } catch {
            throw KernelError.wrapping(error, phase: .evaluation,
                featureID: feature.id, tolerance: context.tolerance)
        }
    }
}
