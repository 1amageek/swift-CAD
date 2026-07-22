import Foundation
import CADCore
import CADGeometry
import CADIR

public struct CurveExtendFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
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
        guard case let .curveExtend(extensionRequest) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Curve extend evaluator requires a curveExtend feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try extensionRequest.validate()
        }
        let distance = try resolvedDistance(
            extensionRequest.distance,
            featureID: feature.id,
            context: context
        )
        let source = try sourceCurve(
            extensionRequest.source,
            featureID: feature.id,
            context: context
        )
        let output = try extendedCurve(
            featureID: feature.id,
            source: source,
            end: extensionRequest.end,
            distance: distance,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedCurves: [output]
        )
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: "curveExtend.distance", expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite, quantity.value > context.tolerance.distance else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Curve extension distance must be a positive length above modeling tolerance."
            )
        }
        return quantity.value
    }

    private func sourceCurve(
        _ reference: CurveOutputReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves = context.curves[reference.featureID],
              reference.curveIndex < curves.count else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                tolerance: context.tolerance,
                "Curve extend source could not be resolved."
            )
        }
        let source = curves[reference.curveIndex]
        try source.validate(tolerance: context.tolerance)
        guard source.exactCurve != nil else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: context.tolerance,
                "Curve extend requires an exact source curve."
            )
        }
        return source
    }

    private func extendedCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        end: CurveExtensionEnd,
        distance: Double,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard let exactCurve = source.exactCurve,
              case let .closed(sourceLower, sourceUpper) = source.parameterDomain else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Curve extend requires a finite source parameter domain."
            )
        }
        switch exactCurve {
        case .line, .analytic(.line):
            return try evaluatedCurve(
                featureID: featureID,
                source: source,
                exactCurve: exactCurve,
                domain: extendedDomain(
                    lower: sourceLower,
                    upper: sourceUpper,
                    increment: distance,
                    end: end
                ),
                kind: .line,
                tolerance: tolerance
            )
        case let .circle(circle):
            return try extendedCircle(
                featureID: featureID,
                source: source,
                exactCurve: exactCurve,
                radius: circle.radius,
                sourceLower: sourceLower,
                sourceUpper: sourceUpper,
                end: end,
                distance: distance,
                tolerance: tolerance
            )
        case let .analytic(.arc(center, normal, radius, _, _)):
            let domain = try circularDomain(
                sourceLower: sourceLower,
                sourceUpper: sourceUpper,
                radius: radius,
                end: end,
                distance: distance,
                featureID: featureID,
                tolerance: tolerance
            )
            guard case let .closed(lower, upper) = domain else {
                throw kernelError(.topologyFailure, featureID: featureID, tolerance: tolerance, "Curve extension produced an invalid arc domain.")
            }
            return try evaluatedCurve(
                featureID: featureID,
                source: source,
                exactCurve: .analytic(.arc(
                    center: center,
                    normal: normal,
                    radius: radius,
                    startAngle: lower,
                    endAngle: upper
                )),
                domain: domain,
                kind: .arc,
                isClosed: upper - lower >= 2.0 * .pi - tolerance.angle,
                tolerance: tolerance
            )
        case let .analytic(.circle(_, _, radius)):
            return try extendedCircle(
                featureID: featureID,
                source: source,
                exactCurve: exactCurve,
                radius: radius,
                sourceLower: sourceLower,
                sourceUpper: sourceUpper,
                end: end,
                distance: distance,
                tolerance: tolerance
            )
        case .analytic(.ellipse),
             .analytic(.hyperbola),
             .analytic(.parabola),
             .analytic(.planeTorus),
             .bSpline,
             .implicit,
             .surfaceLift:
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Exact curve extension is unavailable for this curve representation."
            )
        }
    }

    private func extendedCircle(
        featureID: FeatureID,
        source: EvaluatedCurve,
        exactCurve: Curve3D,
        radius: Double,
        sourceLower: Double,
        sourceUpper: Double,
        end: CurveExtensionEnd,
        distance: Double,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        let domain = try circularDomain(
            sourceLower: sourceLower,
            sourceUpper: sourceUpper,
            radius: radius,
            end: end,
            distance: distance,
            featureID: featureID,
            tolerance: tolerance
        )
        return try evaluatedCurve(
            featureID: featureID,
            source: source,
            exactCurve: exactCurve,
            domain: domain,
            kind: .arc,
            isClosed: {
                guard case let .closed(lower, upper) = domain else {
                    return false
                }
                return upper - lower >= 2.0 * .pi - tolerance.angle
            }(),
            tolerance: tolerance
        )
    }

    private func circularDomain(
        sourceLower: Double,
        sourceUpper: Double,
        radius: Double,
        end: CurveExtensionEnd,
        distance: Double,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> ParameterDomain {
        let domain = extendedDomain(
            lower: sourceLower,
            upper: sourceUpper,
            increment: distance / radius,
            end: end
        )
        guard case let .closed(lower, upper) = domain,
              upper - lower <= 2.0 * .pi + tolerance.angle else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Circular extension cannot exceed one full revolution."
            )
        }
        return domain
    }

    private func extendedDomain(
        lower: Double,
        upper: Double,
        increment: Double,
        end: CurveExtensionEnd
    ) -> ParameterDomain {
        switch end {
        case .start:
            return .closed(lower - increment, upper)
        case .end:
            return .closed(lower, upper + increment)
        case .both:
            return .closed(lower - increment, upper + increment)
        }
    }

    private func evaluatedCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        exactCurve: Curve3D,
        domain: ParameterDomain,
        kind: EvaluatedCurveKind,
        isClosed: Bool = false,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard case let .closed(lower, upper) = domain else {
            throw kernelError(.topologyFailure, featureID: featureID, tolerance: tolerance, "Curve extension produced a non-finite domain.")
        }
        let sampleCount = 33
        let points = try (0..<sampleCount).map { index in
            try exactCurve.point(
                at: lower + (upper - lower) * Double(index) / Double(sampleCount - 1),
                tolerance: tolerance
            )
        }
        let output = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: kind,
            points: points,
            isClosed: isClosed,
            plane: source.plane,
            exactCurve: exactCurve,
            exactParameterDomain: domain
        )
        try output.validate(tolerance: tolerance)
        return output
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
