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
        guard case let .bSpline(sourceSpline)? = source.exactCurve,
              sourceSpline.degree == 3,
              sourceSpline.controlPoints.count == 4,
              sourceSpline.weights.allSatisfy({ abs($0 - 1.0) <= tolerance.distance }),
              isSingleClampedSpan(sourceSpline, tolerance: tolerance) else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Exact curve match currently requires one non-rational clamped cubic Bezier span."
            )
        }
        guard let targetCurve = target.exactCurve else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: tolerance, "Curve match target exact geometry is missing.")
        }
        let targetParameter = try endpointParameter(
            target.parameterDomain,
            end: targetEnd,
            featureID: featureID,
            tolerance: tolerance
        )
        let targetFrame = try CurveContinuityTarget(
            curve: targetCurve,
            parameter: targetParameter,
            orientation: targetOrientation
        ).frame(tolerance: tolerance)
        var controlPoints = sourceSpline.controlPoints
        let handleLength: Double
        switch sourceEnd {
        case .start:
            handleLength = (controlPoints[1] - controlPoints[0]).length
        case .end:
            handleLength = (controlPoints[3] - controlPoints[2]).length
        }
        guard handleLength > tolerance.distance else {
            throw kernelError(
                .singularSystem,
                featureID: featureID,
                tolerance: tolerance,
                "Curve match source endpoint handle is singular."
            )
        }
        applyPosition(targetFrame.position, to: sourceEnd, controlPoints: &controlPoints)
        if continuity >= .tangent {
            applyTangent(
                targetFrame.tangent,
                handleLength: handleLength,
                to: sourceEnd,
                controlPoints: &controlPoints
            )
        }
        if continuity >= .curvature {
            guard case let .closed(lower, upper) = sourceSpline.domain else {
                throw kernelError(.topologyFailure, featureID: featureID, tolerance: tolerance, "Curve match source has no finite spline domain.")
            }
            applyCurvature(
                targetFrame.curvatureVector,
                parameterSpan: upper - lower,
                handleLength: handleLength,
                to: sourceEnd,
                controlPoints: &controlPoints
            )
        }
        let matchedSpline = BSplineCurve3D(
            degree: sourceSpline.degree,
            knots: sourceSpline.knots,
            controlPoints: controlPoints,
            weights: sourceSpline.weights
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
        return try evaluatedCurve(
            featureID: featureID,
            source: source,
            curve: matchedSpline,
            tolerance: tolerance
        )
    }

    private func isSingleClampedSpan(
        _ curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard curve.knots.count == 8,
              let lower = curve.knots.first,
              let upper = curve.knots.last else {
            return false
        }
        return curve.knots.prefix(4).allSatisfy { abs($0 - lower) <= tolerance.distance }
            && curve.knots.suffix(4).allSatisfy { abs($0 - upper) <= tolerance.distance }
            && upper - lower > tolerance.distance
    }

    private func endpointParameter(
        _ domain: ParameterDomain,
        end: CurveEndpointEnd,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard case let .closed(lower, upper) = domain else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Curve match requires a finite target endpoint."
            )
        }
        return end == .start ? lower : upper
    }

    private func applyPosition(
        _ position: Point3D,
        to end: CurveEndpointEnd,
        controlPoints: inout [Point3D]
    ) {
        controlPoints[end == .start ? 0 : 3] = position
    }

    private func applyTangent(
        _ tangent: Vector3D,
        handleLength: Double,
        to end: CurveEndpointEnd,
        controlPoints: inout [Point3D]
    ) {
        switch end {
        case .start:
            controlPoints[1] = controlPoints[0] + tangent * handleLength
        case .end:
            controlPoints[2] = controlPoints[3] + tangent * (-handleLength)
        }
    }

    private func applyCurvature(
        _ curvatureVector: Vector3D,
        parameterSpan: Double,
        handleLength: Double,
        to end: CurveEndpointEnd,
        controlPoints: inout [Point3D]
    ) {
        let speed = 3.0 * handleLength / parameterSpan
        let secondDerivative = curvatureVector * (speed * speed)
        let adjustment = secondDerivative * (parameterSpan * parameterSpan / 6.0)
        switch end {
        case .start:
            controlPoints[2] = controlPoints[0]
                + (controlPoints[1] - controlPoints[0]) * 2.0
                + adjustment
        case .end:
            controlPoints[1] = controlPoints[3]
                + (controlPoints[2] - controlPoints[3]) * 2.0
                + adjustment
        }
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

    private func evaluatedCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
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
            plane: source.plane,
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
