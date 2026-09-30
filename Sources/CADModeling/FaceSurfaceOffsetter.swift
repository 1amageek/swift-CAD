import Foundation
import CADCore
import CADGeometry
import CADTopology

/// The surface a face lies on once pushed a distance along its outward side (Push Face, and the
/// walls of Hollow and Thicken Face). Planes, cylinders, cones, spheres and tori offset to
/// surfaces of their own kind; any other surface becomes its exact procedural offset. Every
/// result is checked to hold the pushed image of a point of the face's surface.
package struct FaceSurfaceOffsetter: Sendable {
    package init() {}

    /// `surface` moved `distance` along the outward side a face on it with `orientation` has; a
    /// negative distance moves it inward.
    package func offset(
        _ surface: Surface3D,
        orientation: Orientation,
        by distance: Double,
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        try tolerance.validate()
        guard distance.isFinite else {
            throw failure(.invalidInput, tolerance, "An offset distance must be finite.")
        }
        // The displacement along the surface's own normal.
        let along = orientation == .forward ? distance : -distance
        let (u, v) = sampleParameters(of: surface)
        let sample = try surface.differentialGeometry(u: u, v: v, tolerance: tolerance)
        let normal = try sample.normal.normalized(tolerance: tolerance.distance)
        let result: Surface3D
        switch surface {
        case let .plane(plane):
            let unit = try plane.normal.normalized(tolerance: tolerance.distance)
            result = .plane(Plane3D(origin: plane.origin + unit * along * (unit.dot(normal) > 0 ? 1 : -1), normal: plane.normal))
        case let .analytic(.plane(origin, planeNormal)):
            let unit = try planeNormal.normalized(tolerance: tolerance.distance)
            result = .analytic(.plane(origin: origin + unit * along * (unit.dot(normal) > 0 ? 1 : -1), normal: planeNormal))
        case let .cylinder(cylinder):
            result = .cylinder(Cylinder3D(
                origin: cylinder.origin, axis: cylinder.axis,
                radius: try offsetRadius(cylinder.radius, along: along, normal: normal, from: sample.position,
                                         axisOrigin: cylinder.origin, axis: cylinder.axis, tolerance: tolerance)
            ))
        case let .analytic(.cylinder(origin, axis, radius)):
            result = .analytic(.cylinder(
                origin: origin, axis: axis,
                radius: try offsetRadius(radius, along: along, normal: normal, from: sample.position,
                                         axisOrigin: origin, axis: axis, tolerance: tolerance)
            ))
        case let .analytic(.sphere(center, radius)):
            let away = normal.dot(sample.position - center) > 0
            result = .analytic(.sphere(center: center, radius: try positive(radius + (away ? along : -along), tolerance)))
        case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
            let unitAxis = try axis.normalized(tolerance: tolerance.distance)
            let radial = sample.position - center - unitAxis * unitAxis.dot(sample.position - center)
            let tubeCenter = center + (try radial.normalized(tolerance: tolerance.distance)) * majorRadius
            let away = normal.dot(sample.position - tubeCenter) > 0
            let minor = try positive(minorRadius + (away ? along : -along), tolerance)
            guard minor < majorRadius else {
                throw failure(.unsupportedCapability, tolerance, "Offsetting a torus past its major radius would make it cross itself.")
            }
            result = .analytic(.torus(center: center, axis: axis, majorRadius: majorRadius, minorRadius: minor))
        case let .analytic(.cone(apex, axis, halfAngle)):
            // A cone's offset is the same cone slid along its axis: moving each ruling a
            // distance d away from the axis moves the apex d / sin(halfAngle) back along it.
            let unitAxis = try axis.normalized(tolerance: tolerance.distance)
            let radial = sample.position - apex - unitAxis * unitAxis.dot(sample.position - apex)
            let away = normal.dot(radial) > 0
            let shift = (away ? along : -along) / sin(halfAngle)
            result = .analytic(.cone(apex: apex + unitAxis * -shift, axis: axis, halfAngle: halfAngle))
        default:
            result = .procedural(.offset(OffsetSurface3D(source: surface, distance: along)))
        }
        try result.validate(tolerance: tolerance)
        // The pushed image of the sample lies on the result.
        let image = sample.position + normal * along
        guard case let .projected(projection) = try result.parameterProjectionResult(of: image, tolerance: tolerance),
              (try result.differentialGeometry(u: projection.u, v: projection.v, tolerance: tolerance).position - image).length <= tolerance.distance else {
            throw failure(.topologyFailure, tolerance, "An offset surface does not hold its pushed face.")
        }
        return result
    }

    private func offsetRadius(
        _ radius: Double, along: Double, normal: Vector3D, from point: Point3D,
        axisOrigin: Point3D, axis: Vector3D, tolerance: ModelingTolerance
    ) throws -> Double {
        let unitAxis = try axis.normalized(tolerance: tolerance.distance)
        let radial = point - axisOrigin - unitAxis * unitAxis.dot(point - axisOrigin)
        return try positive(radius + (normal.dot(radial) > 0 ? along : -along), tolerance)
    }

    private func positive(_ radius: Double, _ tolerance: ModelingTolerance) throws -> Double {
        guard radius > tolerance.distance else {
            throw failure(.topologyFailure, tolerance, "An offset shrinks a curved face to nothing.")
        }
        return radius
    }

    /// A parameter pair inside the surface's domain.
    private func sampleParameters(of surface: Surface3D) -> (Double, Double) {
        func middle(_ domain: ParameterDomain) -> Double {
            switch domain {
            case .unbounded: 1
            case .periodic: 0
            case let .closed(lower, upper): (lower + upper) / 2
            }
        }
        return (middle(surface.uDomain), middle(surface.vDomain))
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, tolerance: tolerance, message: message)
    }
}
