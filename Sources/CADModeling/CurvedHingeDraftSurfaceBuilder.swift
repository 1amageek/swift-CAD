import Foundation
import CADCore
import CADGeometry

/// Constructs a ruled draft only when the original analytic geometry proves a common apex.
package struct CurvedHingeDraftSurfaceBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func surface(
        hinge: Curve3D, start: Double, end: Double,
        reference: Surface3D, referenceSign: Double,
        outward: Vector3D, angle: Double, reach: Double
    ) throws -> Surface3D {
        try tolerance.validate()
        try hinge.validate(tolerance: tolerance)
        try reference.validate(tolerance: tolerance)
        try outward.validateUnitLength(tolerance: tolerance)
        guard start.isFinite, end.isFinite, start != end,
              try hinge.parameterDomain.containsSpan(from: start, to: end, tolerance: tolerance),
              referenceSign == 1 || referenceSign == -1,
              angle.isFinite, reach.isFinite, reach > tolerance.distance else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A curved hinge draft requires a finite original trim, oriented reference and reach.")
        }
        let circle: Circle3D?
        switch hinge {
        case let .circle(value): circle = value
        case let .analytic(.circle(center, normal, radius)):
            circle = Circle3D(center: center, normal: normal, radius: radius)
        case let .analytic(.arc(center, normal, radius, _, _)):
            circle = Circle3D(center: center, normal: normal, radius: radius)
        default: circle = nil
        }
        if let circle,
           let cone = try cone(circle: circle, reference: reference, referenceSign: referenceSign,
                               outward: outward, tangent: tan(angle)) {
            return cone
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): General curved hinges do not yet have original
        // whole-range normal/ruling and adjacent-face authority. Production curved-reference
        // FaceDraftFeatureEvaluator dispatch reaches this refusal. Complete only when the
        // original ruled draft and all adjacent intersections are certified over their trims.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                          message: "A curved hinge draft has no original whole-range ruling certificate.")
    }

    /// Coaxial cylinders and equatorial spheres have radial normals on the complete circle.
    /// With the face normal on its axis, every original ruling reaches this same apex.
    private func cone(circle: Circle3D, reference: Surface3D, referenceSign: Double,
                      outward: Vector3D, tangent: Double) throws -> Surface3D? {
        // These identities are structural admission, not an angular or sampled approximation.
        guard circle.normal.cross(outward).length == 0, tangent.isFinite else { return nil }
        let support: (origin: Point3D, axis: Vector3D, radius: Double)?
        switch reference {
        case let .cylinder(value): support = (value.origin, value.axis, value.radius)
        case let .analytic(.cylinder(origin, axis, radius)): support = (origin, axis, radius)
        case let .analytic(.sphere(center, radius)):
            guard center == circle.center, radius == circle.radius else { return nil }
            support = nil
        default: return nil
        }
        if let support {
            guard support.axis.cross(circle.normal).length == 0,
                  (circle.center - support.origin).cross(support.axis).length == 0,
                  support.radius == circle.radius else { return nil }
        }
        let across = try outward.normalized(tolerance: tolerance.distance)
        let apex = circle.center + across * (referenceSign * circle.radius * tangent)
        let height = (circle.center - apex).length
        guard height > tolerance.distance else { return nil }
        return .analytic(.cone(apex: apex,
                               axis: try (circle.center - apex).normalized(tolerance: tolerance.distance),
                               halfAngle: atan2(circle.radius, height)))
    }
}
