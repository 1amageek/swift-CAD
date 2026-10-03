import Foundation
import CADCore
import CADGeometry

/// The nearest point of a whole surface to a point in space, and the surface's unit normal
/// there, for points off the surface as well as on it. Planes, cylinders, spheres, cones and tori
/// are answered in closed form over their full extent; B-spline and procedural surfaces by their
/// certified closest-point projection over their domain.
package struct SurfaceFootResolver: Sendable {
    package init() {}

    package func foot(of point: Point3D, on surface: Surface3D, tolerance: ModelingTolerance) throws -> (point: Point3D, normal: Vector3D) {
        let onSurface: Point3D
        switch surface {
        case let .plane(plane):
            onSurface = try planeFoot(point, origin: plane.origin, normal: plane.normal, tolerance: tolerance)
        case let .analytic(.plane(origin, normal)):
            onSurface = try planeFoot(point, origin: origin, normal: normal, tolerance: tolerance)
        case let .cylinder(cylinder):
            onSurface = try cylinderFoot(point, origin: cylinder.origin, axis: cylinder.axis, radius: cylinder.radius, tolerance: tolerance)
        case let .analytic(.cylinder(origin, axis, radius)):
            onSurface = try cylinderFoot(point, origin: origin, axis: axis, radius: radius, tolerance: tolerance)
        case let .analytic(.sphere(center, radius)):
            // The outward radial direction is the sphere's normal everywhere, its poles included,
            // where the parameterization's frame degenerates.
            let direction = try radialDirection(point - center, tolerance: tolerance)
            return (center + direction * radius, direction)
        case let .analytic(.cone(apex, axis, halfAngle)):
            // The cone runs both ways from its apex: in the half-plane through the axis and the
            // point, the nearer of its two rulings' nearest points.
            let unitAxis = try axis.normalized(tolerance: tolerance.distance)
            let offset = point - apex
            let height = offset.dot(unitAxis)
            let outward = try radialDirection(offset - unitAxis * height, fallback: unitAxis, tolerance: tolerance)
            let radius = offset.dot(outward)
            let candidates = [1.0, -1.0].map { side -> Point3D in
                let along = max(0, side * height * cos(halfAngle) + radius * sin(halfAngle))
                return apex + unitAxis * (side * along * cos(halfAngle)) + outward * (along * sin(halfAngle))
            }
            onSurface = (candidates[0] - point).length <= (candidates[1] - point).length ? candidates[0] : candidates[1]
        case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
            let unitAxis = try axis.normalized(tolerance: tolerance.distance)
            let offset = point - center
            let outward = try radialDirection(offset - unitAxis * offset.dot(unitAxis), fallback: unitAxis, tolerance: tolerance)
            let tube = center + outward * majorRadius
            onSurface = tube + (try radialDirection(point - tube, tolerance: tolerance)) * minorRadius
        case let .bSpline(spline):
            let projection = try spline.closestParameterProjection(of: point, tolerance: tolerance)
            return try frame(on: surface, u: projection.u, v: projection.v, tolerance: tolerance)
        case let .procedural(procedural):
            let projection = try procedural.closestParameterProjection(of: point, options: SurfaceParameterProjectionOptions(), tolerance: tolerance)
            return try frame(on: surface, u: projection.u, v: projection.v, tolerance: tolerance)
        default:
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "The nearest point of this kind of surface is not available.")
        }
        guard case let .projected(projection) = try surface.parameterProjectionResult(of: onSurface, tolerance: tolerance) else {
            throw KernelError(phase: .geometry, code: .topologyFailure, tolerance: tolerance,
                              message: "A surface's nearest point does not lie on it.")
        }
        return try frame(on: surface, u: projection.u, v: projection.v, tolerance: tolerance)
    }

    private func frame(on surface: Surface3D, u: Double, v: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, normal: Vector3D) {
        let geometry = try surface.differentialGeometry(u: u, v: v, tolerance: tolerance)
        return (geometry.position, try geometry.normal.normalized(tolerance: tolerance.distance))
    }

    private func planeFoot(_ point: Point3D, origin: Point3D, normal: Vector3D, tolerance: ModelingTolerance) throws -> Point3D {
        let unit = try normal.normalized(tolerance: tolerance.distance)
        return point + unit * -(point - origin).dot(unit)
    }

    private func cylinderFoot(_ point: Point3D, origin: Point3D, axis: Vector3D, radius: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let unitAxis = try axis.normalized(tolerance: tolerance.distance)
        let offset = point - origin
        let height = offset.dot(unitAxis)
        return origin + unitAxis * height + (try radialDirection(offset - unitAxis * height, tolerance: tolerance)) * radius
    }

    /// The unit direction of `vector`; a point on the axis or at the centre has no nearest point
    /// of its own, so it is refused unless a fallback direction's perpendicular stands in.
    private func radialDirection(_ vector: Vector3D, fallback: Vector3D? = nil, tolerance: ModelingTolerance) throws -> Vector3D {
        if vector.length > tolerance.distance * 1e-3 { return try vector.normalized(tolerance: tolerance.distance * 1e-3) }
        guard let fallback else {
            throw KernelError(phase: .geometry, code: .topologyFailure, tolerance: tolerance,
                              message: "A point at a surface's centre has no single nearest point on it.")
        }
        let seed: Vector3D = abs(fallback.x) < 0.9 ? .unitX : .unitY
        return try fallback.cross(seed).normalized(tolerance: tolerance.distance)
    }
}
