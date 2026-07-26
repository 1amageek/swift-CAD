import CADCore
import Foundation

struct DefaultAnalyticSurfaceImplicitDifferentialEvaluator:
    AnalyticSurfaceImplicitDifferentialEvaluating
{
    func differential(
        at point: Point3D,
        on surface: CanonicalAnalyticSurface
    ) throws -> AnalyticSurfaceImplicitDifferential {
        switch surface {
        case let .plane(plane):
            let relative = point - plane.origin
            return AnalyticSurfaceImplicitDifferential(
                value: relative.dot(plane.normal),
                gradient: plane.normal
            )
        case let .cylinder(cylinder):
            let relative = point - cylinder.origin
            let radial = relative
                - cylinder.axis * relative.dot(cylinder.axis)
            return AnalyticSurfaceImplicitDifferential(
                value: radial.dot(radial)
                    - cylinder.radius * cylinder.radius,
                gradient: radial * 2.0
            )
        case let .cone(cone):
            let relative = point - cone.apex
            let axial = relative.dot(cone.axis)
            let radial = relative - cone.axis * axial
            let tangentSquared = pow(tan(cone.halfAngle), 2.0)
            return AnalyticSurfaceImplicitDifferential(
                value: radial.dot(radial)
                    - axial * axial * tangentSquared,
                gradient: radial * 2.0
                    - cone.axis * (2.0 * axial * tangentSquared)
            )
        case let .sphere(sphere):
            let relative = point - sphere.center
            return AnalyticSurfaceImplicitDifferential(
                value: relative.dot(relative)
                    - sphere.radius * sphere.radius,
                gradient: relative * 2.0
            )
        case let .torus(torus):
            let relative = point - torus.center
            let axial = relative.dot(torus.axis)
            let radial = relative - torus.axis * axial
            let distanceSquared = relative.dot(relative)
            let quadratic = distanceSquared
                + torus.majorRadius * torus.majorRadius
                - torus.minorRadius * torus.minorRadius
            return AnalyticSurfaceImplicitDifferential(
                value: quadratic * quadratic
                    - 4.0 * torus.majorRadius * torus.majorRadius
                        * radial.dot(radial),
                gradient: relative * (4.0 * quadratic)
                    - radial
                        * (8.0 * torus.majorRadius * torus.majorRadius)
            )
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Implicit differential evaluation requires an analytic surface."
            )
        }
    }

    func curveSecondDerivative(
        geometry: Curve3D.DifferentialGeometry,
        implicitGradient: Vector3D,
        surface: CanonicalAnalyticSurface
    ) throws -> Double {
        let tangent = geometry.firstDerivative
        let tangentSquared = tangent.dot(tangent)
        let directionalHessian: Double
        switch surface {
        case .plane:
            directionalHessian = 0.0
        case let .cylinder(cylinder):
            let axial = cylinder.axis.dot(tangent)
            directionalHessian = 2.0 * (
                tangentSquared - axial * axial
            )
        case let .cone(cone):
            let axial = cone.axis.dot(tangent)
            directionalHessian = 2.0 * (
                tangentSquared
                    - axial * axial
                    - axial * axial
                        * pow(tan(cone.halfAngle), 2.0)
            )
        case .sphere:
            directionalHessian = 2.0 * tangentSquared
        case let .torus(torus):
            let relative = geometry.position - torus.center
            let axialTangent = torus.axis.dot(tangent)
            let radialTangentSquared = tangentSquared
                - axialTangent * axialTangent
            let quadratic = relative.dot(relative)
                + torus.majorRadius * torus.majorRadius
                - torus.minorRadius * torus.minorRadius
            directionalHessian =
                8.0 * pow(relative.dot(tangent), 2.0)
                    + 4.0 * quadratic * tangentSquared
                    - 8.0 * torus.majorRadius * torus.majorRadius
                        * radialTangentSquared
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Implicit second-derivative evaluation requires an analytic surface."
            )
        }
        let result = directionalHessian
            + implicitGradient.dot(geometry.secondDerivative)
        guard result.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "Implicit curve second-derivative evaluation exceeded finite arithmetic."
            )
        }
        return result
    }
}
