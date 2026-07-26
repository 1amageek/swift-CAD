import Foundation
import CADCore

struct DefaultCurveSurfaceSearchRangeResolver:
    CurveSurfaceSearchRangeResolving
{
    func curveRange(
        curve: Curve3D,
        surface: Surface3D,
        requestedRange: ScalarInterval?,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        if let requestedRange {
            return requestedRange
        }
        switch curve.parameterDomain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            return try derivedUnboundedRange(
                curve: curve,
                surface: surface,
                tolerance: tolerance
            )
        }
    }

    private func derivedUnboundedRange(
        curve: Curve3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard case let .bSpline(bSplineSurface) = surface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An unbounded adaptive curve requires a bounded target surface or an explicit curve range."
            )
        }
        let bounds = try BoundingBox3D(
            points: bSplineSurface.controlPoints.flatMap { $0 }
        ).expanded(by: tolerance.distance)
        let corners = corners(of: bounds)
        let raw: (lower: Double, upper: Double, metricScale: Double)
        switch curve {
        case let .line(line):
            raw = projectedRange(
                points: corners,
                origin: line.origin,
                axis: line.direction,
                metricScale: 1.0
            )
        case let .analytic(.line(origin, direction)):
            raw = projectedRange(
                points: corners,
                origin: origin,
                axis: direction,
                metricScale: 1.0
            )
        case let .analytic(.parabola(parabola)):
            let transverseAxis = try parabola.normal.cross(parabola.axis)
                .normalized(tolerance: tolerance.distance)
            raw = projectedRange(
                points: corners,
                origin: parabola.vertex,
                axis: transverseAxis,
                metricScale: 1.0
            )
        case let .analytic(.hyperbola(hyperbola)):
            let conjugateAxis = try hyperbola.normal
                .cross(hyperbola.transverseAxis)
                .normalized(tolerance: tolerance.distance)
            let projected = projectedRange(
                points: corners,
                origin: hyperbola.center,
                axis: conjugateAxis,
                metricScale: hyperbola.conjugateRadius
            )
            raw = (
                lower: asinh(
                    projected.lower / hyperbola.conjugateRadius
                ),
                upper: asinh(
                    projected.upper / hyperbola.conjugateRadius
                ),
                metricScale: hyperbola.conjugateRadius
            )
        case .circle, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection,
             .analytic(.circle), .analytic(.arc), .analytic(.ellipse),
             .analytic(.planeTorus):
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The unbounded curve representation has no certified bounded-target parameter projection."
            )
        }
        return try expandedRange(
            lower: raw.lower,
            upper: raw.upper,
            metricScale: raw.metricScale,
            tolerance: tolerance
        )
    }

    private func projectedRange(
        points: [Point3D],
        origin: Point3D,
        axis: Vector3D,
        metricScale: Double
    ) -> (lower: Double, upper: Double, metricScale: Double) {
        let values = points.map { ($0 - origin).dot(axis) }
        return (
            lower: values.min() ?? 0.0,
            upper: values.max() ?? 0.0,
            metricScale: metricScale
        )
    }

    private func expandedRange(
        lower: Double,
        upper: Double,
        metricScale: Double,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        let scale = max(abs(lower), abs(upper), upper - lower, 1.0)
        let padding = max(
            tolerance.relative * scale * 8.0,
            tolerance.distance / max(metricScale, tolerance.distance) * 8.0,
            Double.ulpOfOne * scale * 4_096.0
        )
        let expandedLower = lower - padding
        let expandedUpper = upper + padding
        guard expandedLower.isFinite,
              expandedUpper.isFinite,
              expandedLower < expandedUpper else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: scale,
                tolerance: tolerance,
                message: "Bounded-target curve range derivation exceeded finite arithmetic."
            )
        }
        return try ScalarInterval(
            lower: expandedLower,
            upper: expandedUpper
        )
    }

    private func corners(of box: BoundingBox3D) -> [Point3D] {
        [
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.maximum.z),
        ]
    }
}
