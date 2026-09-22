import CADCore
import Foundation

/// Constructs rolling-ball contact sections using existing offset intersections.
public struct RollingBallSectionEvaluator: RollingBallSectionEvaluating {
    private let first: OffsetSurface3D
    private let second: OffsetSurface3D
    private let intersection: SurfaceSurfaceIntersectionCurve
    private let tolerance: ModelingTolerance

    public init(
        first: OffsetSurface3D,
        second: OffsetSurface3D,
        intersection: SurfaceSurfaceIntersectionCurve,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        guard abs(first.distance) > tolerance.distance,
              abs(first.distance) == abs(second.distance) else {
            throw KernelError(
                phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Rolling-ball offsets require equal, positive radius magnitudes."
            )
        }
        try intersection.validate(tolerance: tolerance)
        self.first = first
        self.second = second
        self.intersection = intersection
        self.tolerance = tolerance
    }

    public func section(atCurveParameter parameter: Double) throws -> RollingBallSection {
        let correspondence = try intersection.evaluatedCorrespondenceAssumingValidated(
            atCurveParameter: parameter,
            firstSurface: .procedural(.offset(first)),
            secondSurface: .procedural(.offset(second)),
            tolerance: tolerance
        )
        let firstParameter = correspondence.parameters.first
        let secondParameter = correspondence.parameters.second
        let firstPoint = try first.source.point(
            u: firstParameter.u, v: firstParameter.v, tolerance: tolerance
        )
        let secondPoint = try second.source.point(
            u: secondParameter.u, v: secondParameter.v, tolerance: tolerance
        )
        let firstNormal = try first.source.normal(
            u: firstParameter.u, v: firstParameter.v, tolerance: tolerance
        )
        let secondNormal = try second.source.normal(
            u: secondParameter.u, v: secondParameter.v, tolerance: tolerance
        )
        let radius = abs(first.distance)
        let center = firstPoint + firstNormal * first.distance
        let otherCenter = secondPoint + secondNormal * second.distance
        let a = firstNormal * (first.distance > 0 ? -1.0 : 1.0)
        let b = secondNormal * (second.distance > 0 ? -1.0 : 1.0)
        let denominator = 1.0 + a.dot(b)
        let angularThreshold = max(
            sin(min(tolerance.angle, .pi * 0.5)), tolerance.relative
        )
        guard denominator.isFinite, denominator > 0,
              a.cross(b).length > angularThreshold else {
            throw KernelError(
                phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "Rolling-ball contacts must define a regular, non-antipodal minor arc."
            )
        }
        let start = center + a * radius
        let end = center + b * radius
        let residual = max(
            correspondence.residual,
            max((center - otherCenter).length,
                max((center - correspondence.point).length,
                    max((start - firstPoint).length, (end - secondPoint).length)))
        )
        guard residual.isFinite, residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry, code: .intersectionFailure,
                residual: residual, tolerance: tolerance,
                message: "Rolling-ball contacts do not share the supplied offset intersection."
            )
        }
        let arc = BSplineCurve3D(
            degree: 2,
            knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [start, center + (a + b) * (radius / denominator), end],
            weights: [1, sqrt(denominator * 0.5), 1]
        )
        try arc.validate(tolerance: tolerance)
        // Large coordinate cancellation must not turn a valid contact normal
        // into a non-tangent stored arc, even when the endpoints still fit.
        let startTangent = try arc.differentialGeometry(at: 0, tolerance: tolerance).tangent
        let endTangent = try arc.differentialGeometry(at: 1, tolerance: tolerance).tangent
        guard abs(startTangent.dot(firstNormal)) <= angularThreshold,
              abs(endTangent.dot(secondNormal)) <= angularThreshold else {
            throw KernelError(
                phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "Stored rolling-ball arc controls cannot retain source contact tangency."
            )
        }
        return RollingBallSection(
            center: center, radius: radius,
            firstContactParameter: firstParameter, secondContactParameter: secondParameter,
            firstContactPoint: firstPoint, secondContactPoint: secondPoint,
            arc: arc, maximumContactResidual: residual
        )
    }
}
