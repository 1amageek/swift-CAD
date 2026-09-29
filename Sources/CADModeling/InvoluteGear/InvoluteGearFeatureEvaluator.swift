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
            // The gear generates both the sweep's section and its path. A sweep's path must be
            // distinct from its sections, so the path takes an identity of its own, derived from
            // the gear's and used only as the sweep's input key.
            let pathID = Self.pathFeatureID(of: feature.id)
            var inputs = context
            inputs.profiles[feature.id] = [profile]
            inputs.curves[pathID] = [EvaluatedCurve(sourceFeatureID: pathID,
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
                path: .init(featureID: pathID), options: .init(
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

    /// The identity of the path a gear sweeps its section along: fixed for a gear, and never the
    /// gear's own identity (UUID version and variant bits kept, as generated topology IDs keep them).
    package static func pathFeatureID(of gearID: FeatureID) -> FeatureID {
        let bits = gearID.bitPattern
        let high = ((bits.high ^ 0x9E37_79B9_7F4A_7C15) & ~UInt64(0xF000)) | 0x8000
        let low = ((bits.low ^ 0xD1B5_4A32_D192_ED03) & 0x3FFF_FFFF_FFFF_FFFF) | 0x8000_0000_0000_0000
        return FeatureID(highBits: high, lowBits: low)
    }
}
