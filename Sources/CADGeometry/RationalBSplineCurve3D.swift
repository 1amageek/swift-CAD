import Foundation
import CADCore

/// A non-rational or rational B-spline curve evaluated in homogeneous coordinates.
public struct RationalBSplineCurve3D: Codable, Equatable, Hashable, Sendable {
    public let controlPoints: [Point3D]
    public let weights: [Double]
    public let knots: [Double]
    public let degree: Int

    public init(
        controlPoints: [Point3D],
        weights: [Double]? = nil,
        knots: [Double],
        degree: Int
    ) {
        self.controlPoints = controlPoints
        self.weights = weights ?? Array(repeating: 1.0, count: controlPoints.count)
        self.knots = knots
        self.degree = degree
    }

    public var parameterDomain: CurveParameterDomain {
        guard degree >= 0, degree < knots.count, knots.count > degree else {
            return .bounded(lower: 0.0, upper: 0.0)
        }
        let upperIndex = knots.count - degree - 1
        guard upperIndex < knots.count else {
            return .bounded(lower: 0.0, upper: 0.0)
        }
        return .bounded(lower: knots[degree], upper: knots[upperIndex])
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        guard controlPoints.count >= 2,
              degree >= 1,
              degree < controlPoints.count else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A B-spline curve requires at least two control points and a valid degree."
            )
        }
        guard weights.count == controlPoints.count else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline weights must match the control point count."
            )
        }
        guard knots.count == controlPoints.count + degree + 1 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline knot count must equal control count plus degree plus one."
            )
        }
        guard knots.allSatisfy(\.isFinite),
              zip(knots.dropFirst(), knots).allSatisfy({ $0 >= $1 }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline knots must be finite and non-decreasing."
            )
        }
        guard weights.allSatisfy({ $0.isFinite && $0 > tolerance.distance }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline weights must be finite and positive."
            )
        }
        try controlPoints.forEach { try $0.validate() }
        try parameterDomain.validate()
        guard parameterDomain.contains(knots[degree], tolerance: tolerance.distance),
              parameterDomain.contains(knots[knots.count - degree - 1], tolerance: tolerance.distance) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline parameter domain is invalid."
            )
        }
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> AnalyticCurve3D.DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard parameterDomain.contains(parameter, tolerance: tolerance.distance) else {
            throw GeometryError.invalidDistance(parameter)
        }
        let h0 = homogeneous(parameter: parameter, derivative: 0)
        let h1 = homogeneous(parameter: parameter, derivative: 1)
        let h2 = homogeneous(parameter: parameter, derivative: 2)
        guard abs(h0.w) > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: abs(h0.w),
                tolerance: tolerance,
                message: "B-spline homogeneous denominator is degenerate."
            )
        }
        let position = Point3D(x: h0.x / h0.w, y: h0.y / h0.w, z: h0.z / h0.w)
        let first = Vector3D(
            x: (h1.x * h0.w - h0.x * h1.w) / (h0.w * h0.w),
            y: (h1.y * h0.w - h0.y * h1.w) / (h0.w * h0.w),
            z: (h1.z * h0.w - h0.z * h1.w) / (h0.w * h0.w)
        )
        guard first.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: first.length,
                tolerance: tolerance,
                message: "B-spline differential geometry has a degenerate first derivative."
            )
        }
        let second = Vector3D(
            x: h2.x / h0.w - 2.0 * h1.x * h1.w / (h0.w * h0.w) + 2.0 * h0.x * h1.w * h1.w / pow(h0.w, 3.0) - h0.x * h2.w / (h0.w * h0.w),
            y: h2.y / h0.w - 2.0 * h1.y * h1.w / (h0.w * h0.w) + 2.0 * h0.y * h1.w * h1.w / pow(h0.w, 3.0) - h0.y * h2.w / (h0.w * h0.w),
            z: h2.z / h0.w - 2.0 * h1.z * h1.w / (h0.w * h0.w) + 2.0 * h0.z * h1.w * h1.w / pow(h0.w, 3.0) - h0.z * h2.w / (h0.w * h0.w)
        )
        let tangent = try first.normalized(tolerance: tolerance.distance)
        let curvature = first.cross(second).length / pow(first.length, 3.0)
        return AnalyticCurve3D.DifferentialGeometry(
            position: position,
            firstDerivative: first,
            secondDerivative: second,
            tangent: tangent,
            curvature: curvature
        )
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance = .standard) throws -> Point3D {
        try differentialGeometry(at: parameter, tolerance: tolerance).position
    }

    private func homogeneous(parameter: Double, derivative: Int) -> (x: Double, y: Double, z: Double, w: Double) {
        var x = 0.0
        var y = 0.0
        var z = 0.0
        var w = 0.0
        for index in controlPoints.indices {
            let basis = RationalBSplineSupport.basis(
                index: index,
                degree: degree,
                parameter: parameter,
                knots: knots,
                derivative: derivative
            )
            let weight = weights[index]
            x += controlPoints[index].x * weight * basis
            y += controlPoints[index].y * weight * basis
            z += controlPoints[index].z * weight * basis
            w += weight * basis
        }
        return (x, y, z, w)
    }
}
