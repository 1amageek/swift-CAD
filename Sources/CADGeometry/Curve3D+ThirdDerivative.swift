import Foundation
import CADCore

extension Curve3D {
    /// C‴ at `parameter`, for the curves whose third derivative is exact: a line, a circle, a
    /// non-rational B-spline and their rigid and affine images. Other curves are refused as an
    /// unsupported capability, which only G3 continuity needs.
    public func thirdParameterDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> Vector3D {
        try validate(tolerance: tolerance)
        return try thirdParameterDerivativeAssumingValid(at: parameter, tolerance: tolerance)
    }

    private func thirdParameterDerivativeAssumingValid(at parameter: Double, tolerance: ModelingTolerance) throws -> Vector3D {
        switch self {
        case .line:
            return .zero
        case let .circle(circle):
            let (u, v) = try circleOrthonormalBasis(circle.normal, tolerance: tolerance)
            return (u * (circle.radius * sin(parameter))) + (v * (-circle.radius * cos(parameter)))
        case let .bSpline(curve):
            guard curve.weights.allSatisfy({ $0 == 1 }) else {
                throw unsupportedThirdDerivative("a rational B-spline", tolerance: tolerance)
            }
            guard try curve.domain.contains(parameter, tolerance: tolerance) else {
                throw GeometryError.invalidDistance(0.0)
            }
            let basis = BSplineBasis.nonzeroDerivativeValues(
                parameter: parameter,
                degree: curve.degree,
                throughDerivativeOrder: 3,
                knots: curve.knots,
                count: curve.controlPointCount
            )[3]
            var result = Vector3D.zero
            for (offset, value) in basis.values.enumerated() {
                let point = curve.controlPoints[basis.startIndex + offset]
                result = result + Vector3D(x: point.x, y: point.y, z: point.z) * value
            }
            guard result.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "B-spline third differentiation exceeded the finite numeric range."
                )
            }
            return result
        case let .rigidImage(image):
            return image.transform.applying(
                to: try image.source.thirdParameterDerivativeAssumingValid(at: parameter, tolerance: tolerance)
            )
        case let .affineImage(image):
            return image.transform.applying(
                to: try image.source.thirdParameterDerivativeAssumingValid(at: parameter, tolerance: tolerance)
            )
        case .analytic:
            throw unsupportedThirdDerivative("an analytic curve", tolerance: tolerance)
        case .implicit, .surfaceLift, .certifiedIntersection:
            throw unsupportedThirdDerivative("an intersection or surface curve", tolerance: tolerance)
        }
    }

    private func unsupportedThirdDerivative(_ kind: String, tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "The third derivative of \(kind) is not available, so it cannot take G3 continuity."
        )
    }
}
