import CADCore
import Foundation

public struct Parabola3D: Codable, Hashable, Sendable {
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
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> AnalyticCurve3D.DifferentialGeometry {
        try validate(tolerance: tolerance)
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

    public func parameter(
        for point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try validate(tolerance: tolerance)
        try point.validate()
        let transverseAxis = try normal.cross(axis).normalized(
            tolerance: tolerance.distance
        )
        return (point - vertex).dot(transverseAxis)
    }
}
