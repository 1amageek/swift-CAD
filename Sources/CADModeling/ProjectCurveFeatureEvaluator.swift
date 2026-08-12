import Foundation
import CADCore
import CADGeometry
import CADIR

public struct ProjectCurveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
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
        guard case let .projectCurve(projectCurve) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Curve projection evaluator requires a projectCurve feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try projectCurve.validate(tolerance: context.tolerance)
        }
        let source = try sourceCurve(projectCurve.source, featureID: feature.id, context: context)
        let generatedCurve = try projectedCurve(
            featureID: feature.id,
            source: source,
            planeOrigin: projectCurve.planeOrigin,
            planeNormal: projectCurve.planeNormal,
            direction: projectCurve.direction,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedCurves: [generatedCurve]
        )
    }

    private func sourceCurve(
        _ reference: CurveOutputReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves = context.curves[reference.featureID] else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve projection source feature could not be resolved.")
        }
        guard reference.curveIndex < curves.count else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve projection source index could not be resolved.")
        }
        let curve = curves[reference.curveIndex]
        try curve.validate(tolerance: context.tolerance)
        guard curve.exactCurve != nil else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Curve projection requires an exact source curve.")
        }
        return curve
    }

    private func projectedCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        direction: Vector3D?,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard let exactCurve = source.exactCurve else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Curve projection requires an exact source curve.")
        }
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        let projectionDirection = try (direction ?? planeNormal).normalized(tolerance: tolerance.distance)
        let projection = ParallelPlaneProjection(
            planeOrigin: planeOrigin,
            planeNormal: normal,
            direction: projectionDirection
        )
        switch exactCurve {
        case let .line(line):
            return try projectLine(
                featureID: featureID,
                source: source,
                line: line,
                projection: projection,
                tolerance: tolerance
            )
        case let .bSpline(curve):
            return try projectBSpline(
                featureID: featureID,
                source: source,
                curve: curve,
                projection: projection,
                tolerance: tolerance
            )
        case let .circle(circle):
            return try projectCircle(
                featureID: featureID,
                source: source,
                circle: circle,
                projection: projection,
                tolerance: tolerance
            )
        case .analytic, .implicit, .surfaceLift, .certifiedIntersection:
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                "Curve projection supports exact line, circle, and B-spline sources only."
            )
        }
    }

    private func projectLine(
        featureID: FeatureID,
        source: EvaluatedCurve,
        line: Line3D,
        projection: ParallelPlaneProjection,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        try line.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = source.parameterDomain else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: tolerance,
                "Curve projection requires a finite trim domain on a line source."
            )
        }
        let start = projection.apply(line.origin + line.direction * lower)
        let end = projection.apply(line.origin + line.direction * upper)
        let projectedSpan = end - start
        let projectedLength = projectedSpan.length
        guard projectedLength > tolerance.distance else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: tolerance,
                "Curve projection collapses the source line to a degenerate segment."
            )
        }
        let projectedDirection = try projectedSpan.normalized(tolerance: tolerance.distance)
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .line,
            points: source.points.map(projection.apply),
            plane: .plane(Plane3D(origin: projection.planeOrigin, normal: projection.planeNormal)),
            exactCurve: .line(Line3D(origin: start, direction: projectedDirection)),
            exactParameterDomain: .closed(0.0, projectedLength)
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }

    private func projectBSpline(
        featureID: FeatureID,
        source: EvaluatedCurve,
        curve: BSplineCurve3D,
        projection: ParallelPlaneProjection,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        // Parallel projection is affine, so projecting every control point yields
        // the exact projected B-spline with unchanged degree, knots, and weights.
        let projected = BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map(projection.apply),
            weights: curve.weights
        )
        try projected.validate(tolerance: tolerance)
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: source.kind,
            points: source.points.map(projection.apply),
            isClosed: source.isClosed,
            plane: .plane(Plane3D(origin: projection.planeOrigin, normal: projection.planeNormal)),
            exactCurve: .bSpline(projected),
            exactParameterDomain: source.exactParameterDomain
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }

    private func projectCircle(
        featureID: FeatureID,
        source: EvaluatedCurve,
        circle: Circle3D,
        projection: ParallelPlaneProjection,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        try circle.validate(tolerance: tolerance)
        let circleNormal = try circle.normal.normalized(tolerance: tolerance.distance)
        // A parallel projection maps a circle onto a congruent translated circle
        // only when the projection direction and the target plane normal are both
        // parallel to the circle normal; every other configuration produces an
        // ellipse that has no exact circular representation.
        guard circleNormal.cross(projection.direction).length <= sin(tolerance.angle),
              circleNormal.cross(projection.planeNormal).length <= sin(tolerance.angle) else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                "Curve projection of a circle off its axis requires an elliptical projection construction that is not yet available."
            )
        }
        let projectedCircle = Circle3D(
            center: projection.apply(circle.center),
            normal: circle.normal,
            radius: circle.radius
        )
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: source.kind == .arc ? .arc : .circle,
            points: source.points.map(projection.apply),
            isClosed: source.isClosed,
            plane: .plane(Plane3D(origin: projection.planeOrigin, normal: projection.planeNormal)),
            exactCurve: .circle(projectedCircle),
            exactParameterDomain: source.exactParameterDomain
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }

    private func kernelError(
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

private struct ParallelPlaneProjection {
    let planeOrigin: Point3D
    let planeNormal: Vector3D
    let direction: Vector3D

    func apply(_ point: Point3D) -> Point3D {
        let offset = (point - planeOrigin).dot(planeNormal) / direction.dot(planeNormal)
        return point + direction * (-offset)
    }
}
