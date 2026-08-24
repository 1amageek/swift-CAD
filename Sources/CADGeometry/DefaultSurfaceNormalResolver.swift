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
                u: u,
                v: v,
                tolerance: tolerance
            )
        case let .bSpline(surface):
            return try surface.normal(
                u: u,
                v: v,
                tolerance: tolerance
            )
        case let .procedural(surface):
            let derivatives = try surface.parameterDerivatives(
                atU: u,
                v: v,
                tolerance: tolerance
            )
            return try derivatives.tangentU.cross(
                derivatives.tangentV
            ).normalized(tolerance: tolerance.distance)
        }
    }

    private func analyticNormal(
        at point: Point3D,
        on surface: AnalyticSurface3D,
        u: Double,
        v: Double,
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
        case let .cone(_, axis, halfAngle):
            // The cone apex is singular as a surface point, but a requested
            // parameter u still identifies a ruling and therefore its unique
            // one-sided limiting normal. Reconstructing the radial direction
            // from the coincident apex discards that information and produces
            // a zero-length vector.
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let radial = basis.u * cos(u) + basis.v * sin(u)
            let sign = v >= 0.0 ? 1.0 : -1.0
            return try (
                radial * (sign * cos(halfAngle))
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
