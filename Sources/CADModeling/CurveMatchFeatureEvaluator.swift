import Foundation
import CADCore
import CADGeometry
import CADIR

public struct CurveMatchFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    public init() {}

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
        guard case let .curveMatch(match) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Curve match evaluator requires a curveMatch feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try match.validate()
        }
        let source = try curve(match.source, owner: "source", featureID: feature.id, context: context)
        let target = try curve(match.target, owner: "target", featureID: feature.id, context: context)
        let output = try matchedCurve(
            featureID: feature.id,
            source: source,
            sourceEnd: match.sourceEnd,
            target: target,
            targetEnd: match.targetEnd,
            targetOrientation: match.targetOrientation,
            continuity: match.continuity,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedCurves: [output]
        )
    }

    private func curve(
        _ reference: CurveOutputReference,
        owner: String,
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
                "Curve match \(owner) could not be resolved."
            )
        }
        let curve = curves[reference.curveIndex]
        try curve.validate(tolerance: context.tolerance)
        guard curve.exactCurve != nil else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: context.tolerance,
                "Curve match \(owner) must be exact."
            )
        }
        return curve
    }

    private func matchedCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        sourceEnd: CurveEndpointEnd,
        target: EvaluatedCurve,
        targetEnd: CurveEndpointEnd,
        targetOrientation: CurveFrameOrientation,
        continuity: CurveContinuityLevel,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard let sourceCurve = source.exactCurve,
              let targetCurve = target.exactCurve else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                tolerance: tolerance,
                "Curve match exact geometry is missing."
            )
        }
        let sourceBounds = try finiteBounds(
            source.parameterDomain,
            owner: "source",
            featureID: featureID,
            tolerance: tolerance
        )
        let targetBounds = try finiteBounds(
            target.parameterDomain,
            owner: "target",
            featureID: featureID,
            tolerance: tolerance
        )
        let targetParameter = targetEnd == .start ? targetBounds.lower : targetBounds.upper
        let targetFrame = try CurveContinuityTarget(
            curve: targetCurve,
            parameter: targetParameter,
            orientation: targetOrientation
        ).frame(tolerance: tolerance)
        let sourceSpan = sourceBounds.upper - sourceBounds.lower
        var startJet = try endpointJet(
            curve: sourceCurve,
            parameter: sourceBounds.lower,
            parameterScale: sourceSpan,
            tolerance: tolerance
        )
        var endJet = try endpointJet(
            curve: sourceCurve,
            parameter: sourceBounds.upper,
            parameterScale: sourceSpan,
            tolerance: tolerance
        )
        let originalStartJet = startJet
        let originalEndJet = endJet
        switch sourceEnd {
        case .start:
            startJet = try matchedJet(
                source: startJet,
                target: targetFrame,
                continuity: continuity,
                featureID: featureID,
                tolerance: tolerance
            )
        case .end:
            endJet = try matchedJet(
                source: endJet,
                target: targetFrame,
                continuity: continuity,
                featureID: featureID,
                tolerance: tolerance
            )
        }
        let controlPoints = quinticControlPoints(start: startJet, end: endJet)
        let matchedSpline = BSplineCurve3D(
            degree: 5,
            knots: Array(repeating: 0.0, count: 6) + Array(repeating: 1.0, count: 6),
            controlPoints: controlPoints
        )
        try matchedSpline.validate(tolerance: tolerance)
        try verifyContinuity(
            featureID: featureID,
            curve: matchedSpline,
            sourceEnd: sourceEnd,
            targetCurve: targetCurve,
            targetParameter: targetParameter,
            targetOrientation: targetOrientation,
            requiredLevel: continuity,
            tolerance: tolerance
        )
        try verifyPreservedEndpoint(
            featureID: featureID,
            curve: matchedSpline,
            sourceEnd: sourceEnd,
            originalStartJet: originalStartJet,
            originalEndJet: originalEndJet,
            tolerance: tolerance
        )
        return try evaluatedCurve(
            featureID: featureID,
            curve: matchedSpline,
            tolerance: tolerance
        )
    }

    private struct EndpointJet {
        let position: Point3D
        let firstDerivative: Vector3D
        let secondDerivative: Vector3D
    }

    private func finiteBounds(
        _ domain: ParameterDomain,
        owner: String,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        switch domain {
        case let .closed(lower, upper):
            return (lower, upper)
        case let .periodic(period):
            return (0.0, period)
        case .unbounded:
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                "Curve match \(owner) must expose a finite endpoint domain."
            )
        }
    }

    private func endpointJet(
        curve: Curve3D,
        parameter: Double,
        parameterScale: Double,
        tolerance: ModelingTolerance
    ) throws -> EndpointJet {
        let geometry = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        let firstDerivative = geometry.firstDerivative * parameterScale
        let secondDerivative = geometry.secondDerivative * (parameterScale * parameterScale)
        guard firstDerivative.isFinite,
              secondDerivative.isFinite,
              firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "Curve match requires regular finite source endpoint derivatives."
            )
        }
        return EndpointJet(
            position: geometry.position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    private func matchedJet(
        source: EndpointJet,
        target: CurveContinuityFrame,
        continuity: CurveContinuityLevel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> EndpointJet {
        guard continuity >= .tangent else {
            return EndpointJet(
                position: target.position,
                firstDerivative: source.firstDerivative,
                secondDerivative: source.secondDerivative
            )
        }
        let speed = source.firstDerivative.length
        guard speed.isFinite, speed > tolerance.distance else {
            throw kernelError(
                .singularSystem,
                featureID: featureID,
                tolerance: tolerance,
                "Curve match source endpoint speed is singular."
            )
        }
        let sourceTangent = try source.firstDerivative.normalized(tolerance: tolerance.distance)
        let tangentialAcceleration = source.secondDerivative.dot(sourceTangent)
        let normalAcceleration = continuity >= .curvature
            ? target.curvatureVector * (speed * speed)
            : .zero
        let secondDerivative = target.tangent * tangentialAcceleration + normalAcceleration
        guard secondDerivative.isFinite else {
            throw kernelError(
                .resourceLimitExceeded,
                featureID: featureID,
                tolerance: tolerance,
                "Curve match endpoint jet exceeded the finite numeric range."
            )
        }
        return EndpointJet(
            position: target.position,
            firstDerivative: target.tangent * speed,
            secondDerivative: secondDerivative
        )
    }

    private func quinticControlPoints(
        start: EndpointJet,
        end: EndpointJet
    ) -> [Point3D] {
        [
            start.position,
            start.position + start.firstDerivative / 5.0,
            start.position
                + start.firstDerivative * (2.0 / 5.0)
                + start.secondDerivative / 20.0,
            end.position
                + end.firstDerivative * (-2.0 / 5.0)
                + end.secondDerivative / 20.0,
            end.position + end.firstDerivative * (-1.0 / 5.0),
            end.position,
        ]
    }

    private func verifyContinuity(
        featureID: FeatureID,
        curve: BSplineCurve3D,
        sourceEnd: CurveEndpointEnd,
        targetCurve: Curve3D,
        targetParameter: Double,
        targetOrientation: CurveFrameOrientation,
        requiredLevel: CurveContinuityLevel,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .closed(lower, upper) = curve.domain else {
            throw kernelError(.topologyFailure, featureID: featureID, tolerance: tolerance, "Curve match result has no finite domain.")
        }
        let result = try CurveContinuityEvaluator(modelingTolerance: tolerance).evaluate(
            CurveContinuityRequest(
                first: CurveContinuityTarget(
                    curve: .bSpline(curve),
                    parameter: sourceEnd == .start ? lower : upper
                ),
                second: CurveContinuityTarget(
                    curve: targetCurve,
                    parameter: targetParameter,
                    orientation: targetOrientation
                ),
                requiredLevel: requiredLevel,
                tolerances: .standard(modelingTolerance: tolerance)
            )
        )
        guard result.isSatisfied else {
            let residual = max(
                result.deviation.positionDistance,
                max(result.deviation.tangentAngle, result.deviation.curvatureVectorDistance)
            )
            throw KernelError(
                phase: .geometry,
                code: .conflictingConstraints,
                featureID: featureID,
                residual: residual,
                tolerance: tolerance,
                message: "Curve match could not satisfy the requested continuity."
            )
        }
    }

    private func verifyPreservedEndpoint(
        featureID: FeatureID,
        curve: BSplineCurve3D,
        sourceEnd: CurveEndpointEnd,
        originalStartJet: EndpointJet,
        originalEndJet: EndpointJet,
        tolerance: ModelingTolerance
    ) throws {
        let expected = sourceEnd == .start ? originalEndJet : originalStartJet
        let parameter = sourceEnd == .start ? 1.0 : 0.0
        let actual = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        let expectedTangent = try expected.firstDerivative.normalized(
            tolerance: tolerance.distance
        )
        let expectedSpeed = expected.firstDerivative.length
        let tangentialAcceleration = expectedTangent
            * expected.secondDerivative.dot(expectedTangent)
        let expectedCurvatureVector = (expected.secondDerivative - tangentialAcceleration)
            / (expectedSpeed * expectedSpeed)
        let positionResidual = (actual.position - expected.position).length
        let tangentDot = min(max(actual.tangent.dot(expectedTangent), -1.0), 1.0)
        let tangentResidual = atan2(actual.tangent.cross(expectedTangent).length, tangentDot)
        let curvatureResidual = (actual.curvatureVector - expectedCurvatureVector).length
        let curvatureTolerance = CurveContinuityTolerances
            .standard(modelingTolerance: tolerance)
            .curvatureVector
        guard positionResidual <= tolerance.distance,
              tangentResidual <= tolerance.angle,
              curvatureResidual <= curvatureTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .conflictingConstraints,
                featureID: featureID,
                residual: max(positionResidual, tangentResidual, curvatureResidual),
                tolerance: tolerance,
                message: "Curve match did not preserve the opposite source endpoint G2 jet."
            )
        }
    }

    private func evaluatedCurve(
        featureID: FeatureID,
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard case let .closed(lower, upper) = curve.domain else {
            throw kernelError(.topologyFailure, featureID: featureID, tolerance: tolerance, "Curve match result has no finite domain.")
        }
        let sampleCount = 33
        let points = try (0..<sampleCount).map { index in
            try curve.point(
                at: lower + (upper - lower) * Double(index) / Double(sampleCount - 1),
                tolerance: tolerance
            )
        }
        let output = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .spline,
            points: points,
            exactCurve: .bSpline(curve),
            exactParameterDomain: curve.domain
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
