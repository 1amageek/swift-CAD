import CADCore
import CADGeometry

package struct ExactBSplineCurveSpan: Sendable {
    package let curve: BSplineCurve3D
    package let startPoint: Point3D
    package let endPoint: Point3D

    package init(
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws {
        try curve.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact curve span requires a bounded B-spline."
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
                message: "Exact curve span must be split at a closed seam."
            )
        }
        self.curve = curve
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}
