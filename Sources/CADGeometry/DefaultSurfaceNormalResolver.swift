import CADCore
import Foundation

struct DefaultSurfaceNormalResolver: SurfaceNormalResolving {
    func normal(
        at point: Point3D,
        on surface: Surface3D,
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        switch surface {
        case let .plane(plane):
            return try plane.normal.normalized(
                tolerance: tolerance.distance
            )
        case let .cylinder(cylinder):
            let offset = point - cylinder.origin
            return try (
                offset - cylinder.axis * offset.dot(cylinder.axis)
            ).normalized(tolerance: tolerance.distance)
        case let .analytic(surface):
            return try analyticNormal(
                at: point,
                on: surface,
                tolerance: tolerance
            )
        case .bSpline:
            return try surface.normal(
                u: u,
                v: v,
                tolerance: tolerance
            )
        }
    }

    private func analyticNormal(
        at point: Point3D,
        on surface: AnalyticSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        switch surface {
        case let .plane(_, normal):
            return try normal.normalized(tolerance: tolerance.distance)
        case let .cylinder(origin, axis, _):
            let offset = point - origin
            return try (
                offset - axis * offset.dot(axis)
            ).normalized(tolerance: tolerance.distance)
        case let .cone(apex, axis, halfAngle):
            let offset = point - apex
            let axialDistance = offset.dot(axis)
            let radial = try (
                offset - axis * axialDistance
            ).normalized(tolerance: tolerance.distance)
            let sign = axialDistance >= 0.0 ? 1.0 : -1.0
            return try (
                radial * cos(halfAngle)
                    + axis * (-sign * sin(halfAngle))
            ).normalized(tolerance: tolerance.distance)
        case let .sphere(center, _):
            return try (point - center).normalized(
                tolerance: tolerance.distance
            )
        case let .torus(center, axis, majorRadius, _):
            let offset = point - center
            let radial = offset - axis * offset.dot(axis)
            let radialDirection = try radial.normalized(
                tolerance: tolerance.distance
            )
            return try (
                point - (center + radialDirection * majorRadius)
            ).normalized(tolerance: tolerance.distance)
        }
    }
}
