import CADCore
import CADGeometry

package struct ExactPrismaticBoundarySegment: Sendable {
    package enum Geometry: Sendable {
        case line
        case circularArc(
            circle: Circle3D,
            startParameter: Double,
            endParameter: Double
        )
        case bSpline(BSplineCurve3D)
    }

    package let startPoint: Point3D
    package let endPoint: Point3D
    package let geometry: Geometry

    package static func line(
        from startPoint: Point3D,
        to endPoint: Point3D,
        tolerance: ModelingTolerance
    ) throws -> ExactPrismaticBoundarySegment {
        guard startPoint.isApproximatelyEqual(
            to: endPoint,
            tolerance: tolerance.distance
        ) == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Exact prismatic boundary contains a collapsed line."
            )
        }
        return ExactPrismaticBoundarySegment(
            startPoint: startPoint,
            endPoint: endPoint,
            geometry: .line
        )
    }

    package static func circularArc(
        circle: Circle3D,
        startParameter: Double,
        endParameter: Double,
        tolerance: ModelingTolerance
    ) throws -> ExactPrismaticBoundarySegment {
        try circle.validate(tolerance: tolerance)
        let sweep = endParameter - startParameter
        guard startParameter.isFinite,
              endParameter.isFinite,
              abs(sweep) > tolerance.angle,
              abs(sweep) < 2.0 * Double.pi - tolerance.angle else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact prismatic circular boundary requires a finite non-full arc."
            )
        }
        let curve = Curve3D.circle(circle)
        return ExactPrismaticBoundarySegment(
            startPoint: try curve.point(at: startParameter, tolerance: tolerance),
            endPoint: try curve.point(at: endParameter, tolerance: tolerance),
            geometry: .circularArc(
                circle: circle,
                startParameter: startParameter,
                endParameter: endParameter
            )
        )
    }

    package static func bSpline(
        _ curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> ExactPrismaticBoundarySegment {
        try curve.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact prismatic B-spline boundary requires a bounded curve."
            )
        }
        let startPoint = try curve.point(at: lower, tolerance: tolerance)
        let endPoint = try curve.point(at: upper, tolerance: tolerance)
        guard startPoint.isApproximatelyEqual(
            to: endPoint,
            tolerance: tolerance.distance
        ) == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Exact prismatic B-spline boundary must be split before sewing a closed span."
            )
        }
        return ExactPrismaticBoundarySegment(
            startPoint: startPoint,
            endPoint: endPoint,
            geometry: .bSpline(curve)
        )
    }

    package var sweepAngle: Double? {
        guard case let .circularArc(_, startParameter, endParameter) = geometry else {
            return nil
        }
        return endParameter - startParameter
    }
}
