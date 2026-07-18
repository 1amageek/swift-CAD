import CADCore
import CADGeometry
import CADIR

package struct ExactCircularSweepPath: Sendable, Hashable {
    package let axis: RevolveAxis
    package let angle: Double
    package let startPoint: Point3D
    package let startTangent: Vector3D

    package init?(
        segments: [EvaluatedCurvePathSegment],
        distanceFraction: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard distanceFraction.isFinite,
              distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw FeatureEvaluationError.invalidDistance(distanceFraction)
        }
        guard segments.count == 1,
              let segment = segments.first,
              let curve = segment.curve.exactCurve,
              case let .closed(lower, upper) = segment.curve.parameterDomain else {
            return nil
        }
        let circle: Circle3D
        switch curve {
        case let .circle(value):
            circle = value
        case let .analytic(analytic):
            switch analytic {
            case let .circle(center, normal, radius),
                 let .arc(center, normal, radius, _, _):
                circle = Circle3D(
                    center: center,
                    normal: normal,
                    radius: radius
                )
            case .line, .ellipse:
                return nil
            }
        case .line, .bSpline:
            return nil
        }
        try circle.validate(tolerance: tolerance)
        let span = upper - lower
        guard span.isFinite,
              span > tolerance.angle,
              span <= 2.0 * Double.pi + tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact circular Sweep path requires one bounded angular interval no longer than one turn."
            )
        }
        let startParameter = segment.isReversed ? upper : lower
        let differential = try curve.differentialGeometry(
            at: startParameter,
            tolerance: tolerance
        )
        let directionSign = segment.isReversed ? -1.0 : 1.0
        self.axis = RevolveAxis(
            origin: circle.center,
            direction: circle.normal
        )
        self.angle = directionSign * span * distanceFraction
        self.startPoint = differential.position
        self.startTangent = differential.tangent * directionSign
    }

    package func validateNormalSection(
        plane: SketchPlane,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let sectionPlane = try exactPlane(for: plane, tolerance: tolerance)
        let normal = try sectionPlane.normal.normalized(
            tolerance: tolerance.distance
        )
        let startPlaneResidual = abs(
            (startPoint - sectionPlane.origin).dot(normal)
        )
        guard startPlaneResidual <= tolerance.distance else {
            throw unavailable(
                featureID: featureID,
                residual: startPlaneResidual,
                tolerance: tolerance,
                message: "Exact circular path-normal Sweep requires the path start to lie on the section plane."
            )
        }
        let tangentResidual = abs(1.0 - abs(startTangent.dot(normal)))
        guard tangentResidual <= tolerance.angle else {
            throw unavailable(
                featureID: featureID,
                residual: tangentResidual,
                tolerance: tolerance,
                message: "Exact circular path-normal Sweep requires the section-plane normal to match the initial path tangent."
            )
        }
        let axisDirection = try axis.normalizedDirection(tolerance: tolerance)
        let axisPlaneResidual = abs(
            (axis.origin - sectionPlane.origin).dot(normal)
        )
        let axisDirectionResidual = abs(axisDirection.dot(normal))
        guard axisPlaneResidual <= tolerance.distance else {
            throw unavailable(
                featureID: featureID,
                residual: axisPlaneResidual,
                tolerance: tolerance,
                message: "Exact circular path-normal Sweep requires the circular-axis origin to lie in the section plane."
            )
        }
        guard axisDirectionResidual <= tolerance.angle else {
            throw unavailable(
                featureID: featureID,
                residual: axisDirectionResidual,
                tolerance: tolerance,
                message: "Exact circular path-normal Sweep requires the circular-axis direction to lie in the section plane."
            )
        }
    }

    private func exactPlane(
        for plane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> Plane3D {
        let result: Plane3D
        switch plane {
        case .xy:
            result = Plane3D(origin: .origin, normal: .unitZ)
        case .yz:
            result = Plane3D(origin: .origin, normal: .unitX)
        case .zx:
            result = Plane3D(origin: .origin, normal: .unitY)
        case let .plane(value):
            result = value
        }
        try result.validate(tolerance: tolerance)
        return result
    }

    private func unavailable(
        featureID: FeatureID?,
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .sweepPathNormalUnavailable,
            featureID: featureID,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
