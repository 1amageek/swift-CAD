import Foundation
import CADCore
import CADGeometry

struct ExactAssociatedSurfacePcurveBuilder {
    func build(
        curve: Curve3D,
        modelStart: Point3D,
        modelEnd: Point3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        try tolerance.validate()
        let startParameter = try curve.parameterProjection(
            of: modelStart,
            tolerance: tolerance
        ).parameter
        let projectedEndParameter = try curve.parameterProjection(
            of: modelEnd,
            tolerance: tolerance
        ).parameter

        if case .analytic(.cone) = surface {
            return .projectedAnalytic(
                try ProjectedAnalyticSurfaceParameterCurve(
                    curve: curve,
                    surface: surface,
                    startParameter: startParameter,
                    endParameter: projectedEndParameter,
                    tolerance: tolerance
                )
            )
        }

        guard case let .analytic(.sphere(center, radius)) = surface,
              let definition = circularDefinition(for: curve) else {
            throw KernelError(
                phase: .exchange,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "An exact model-curve surface association requires an open conic on a cone or a great circle on a sphere."
            )
        }
        guard definition.center.isApproximatelyEqual(
            to: center,
            tolerance: tolerance.distance
        ), abs(definition.radius - radius) <= tolerance.distance else {
            throw KernelError(
                phase: .exchange,
                code: .topologyFailure,
                residual: max(
                    (definition.center - center).length,
                    abs(definition.radius - radius)
                ),
                tolerance: tolerance,
                message: "The associated circular model curve is not a great circle of the face sphere."
            )
        }
        let cosine = try (definition.fullCurve.point(
            at: 0.0,
            tolerance: tolerance
        ) - center).normalized(tolerance: tolerance.distance)
        let sine = try (definition.fullCurve.point(
            at: 0.5 * Double.pi,
            tolerance: tolerance
        ) - center).normalized(tolerance: tolerance.distance)
        var endParameter = projectedEndParameter
        if curve.parameterDomain.isPeriodic {
            let period = 2.0 * Double.pi
            while endParameter <= startParameter + tolerance.angle {
                endParameter += period
            }
        }
        let result = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: cosine,
            sine: sine,
            startParameter: startParameter,
            endParameter: endParameter
        )
        try result.validate(on: surface, tolerance: tolerance)
        return result
    }

    private func circularDefinition(
        for curve: Curve3D
    ) -> (center: Point3D, radius: Double, fullCurve: Curve3D)? {
        switch curve {
        case let .circle(circle):
            return (circle.center, circle.radius, curve)
        case let .analytic(.circle(center, normal, radius)),
             let .analytic(.arc(center, normal, radius, _, _)):
            return (
                center,
                radius,
                .analytic(.circle(center: center, normal: normal, radius: radius))
            )
        case .line,
             .analytic,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection:
            return nil
        }
    }
}

private extension ParameterDomain {
    var isPeriodic: Bool {
        if case .periodic = self { return true }
        return false
    }
}
