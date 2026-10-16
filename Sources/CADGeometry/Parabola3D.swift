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

public struct Parabola3D: Hashable, Sendable {
    public let vertex: Point3D
    public let normal: Vector3D
    public let axis: Vector3D
    public let focalLength: Double

    public init(
        vertex: Point3D,
        normal: Vector3D,
        axis: Vector3D,
        focalLength: Double
    ) {
        self.vertex = vertex
        self.normal = normal
        self.axis = axis
        self.focalLength = focalLength
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
        try vertex.validate()
        try normal.validateUnitLength(tolerance: tolerance)
        try axis.validateUnitLength(tolerance: tolerance)
        guard abs(normal.dot(axis)) <= tolerance.angle,
              focalLength.isFinite,
              focalLength > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A parabola requires orthogonal unit axes and a positive finite focal length."
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
        let transverseAxis = try normal.cross(axis).normalized(
            tolerance: tolerance.distance
        )
        let inverseDoubleFocalLength = 1.0 / (2.0 * focalLength)
        let axialDistance = parameter * parameter / (4.0 * focalLength)
        guard axialDistance.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: abs(parameter),
                tolerance: tolerance,
                message: "Parabola evaluation exceeded finite arithmetic."
            )
        }
        return try AnalyticCurve3D.makeDifferentialGeometry(
            position: vertex + transverseAxis * parameter + axis * axialDistance,
            firstDerivative: transverseAxis + axis * (parameter * inverseDoubleFocalLength),
            secondDerivative: axis * inverseDoubleFocalLength,
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
        let transverseAxis = try normal.cross(axis).normalized(
            tolerance: tolerance.distance
        )
        return (point - vertex).dot(transverseAxis)
    }
}

#if !hasFeature(Embedded)
extension Parabola3D: Codable {}
#endif
