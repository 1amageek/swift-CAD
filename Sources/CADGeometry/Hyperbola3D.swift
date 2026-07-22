import CADCore
import Foundation

public struct Hyperbola3D: Codable, Hashable, Sendable {
    public let center: Point3D
    public let normal: Vector3D
    public let transverseAxis: Vector3D
    public let transverseRadius: Double
    public let conjugateRadius: Double

    public init(
        center: Point3D,
        normal: Vector3D,
        transverseAxis: Vector3D,
        transverseRadius: Double,
        conjugateRadius: Double
    ) {
        self.center = center
        self.normal = normal
        self.transverseAxis = transverseAxis
        self.transverseRadius = transverseRadius
        self.conjugateRadius = conjugateRadius
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try center.validate()
        try normal.validateUnitLength(tolerance: tolerance)
        try transverseAxis.validateUnitLength(tolerance: tolerance)
        guard abs(normal.dot(transverseAxis)) <= tolerance.angle,
              transverseRadius.isFinite,
              transverseRadius > tolerance.distance,
              conjugateRadius.isFinite,
              conjugateRadius > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A hyperbola requires orthogonal unit axes and positive finite radii."
            )
        }
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> AnalyticCurve3D.DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        let conjugateAxis = try normal.cross(transverseAxis).normalized(
            tolerance: tolerance.distance
        )
        let hyperbolicCosine = cosh(parameter)
        let hyperbolicSine = sinh(parameter)
        guard hyperbolicCosine.isFinite, hyperbolicSine.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: abs(parameter),
                tolerance: tolerance,
                message: "Hyperbola evaluation exceeded finite arithmetic."
            )
        }
        let position = center
            + transverseAxis * (transverseRadius * hyperbolicCosine)
            + conjugateAxis * (conjugateRadius * hyperbolicSine)
        let firstDerivative = transverseAxis * (transverseRadius * hyperbolicSine)
            + conjugateAxis * (conjugateRadius * hyperbolicCosine)
        let secondDerivative = transverseAxis * (transverseRadius * hyperbolicCosine)
            + conjugateAxis * (conjugateRadius * hyperbolicSine)
        return try AnalyticCurve3D.makeDifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            tolerance: tolerance
        )
    }

    public func parameter(
        for point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try validate(tolerance: tolerance)
        try point.validate()
        let conjugateAxis = try normal.cross(transverseAxis).normalized(
            tolerance: tolerance.distance
        )
        let offset = point - center
        let parameter = asinh(offset.dot(conjugateAxis) / conjugateRadius)
        guard parameter.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Hyperbola inverse parameter evaluation is not finite."
            )
        }
        return parameter
    }
}
