import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

public struct Hyperbola3D: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate<A: ExactScalarAdmission & ~Copyable>(
        tolerance: ModelingTolerance, using execution: inout A
    ) throws {
        try execution.consumeWork(1)
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
        at parameter: Double, tolerance: ModelingTolerance
    ) throws -> AnalyticCurve3D.DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differentialGeometry(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func differentialGeometry<A: ExactScalarAdmission & ~Copyable>(
        at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> AnalyticCurve3D.DifferentialGeometry {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
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

    public func parameter(for point: Point3D, tolerance: ModelingTolerance) throws -> Double {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(for: point, tolerance: tolerance, using: &execution)
    }

    public func parameter<A: ExactScalarAdmission & ~Copyable>(
        for point: Point3D,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Double {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
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

#if !hasFeature(Embedded)
extension Hyperbola3D: Codable {}
#endif
