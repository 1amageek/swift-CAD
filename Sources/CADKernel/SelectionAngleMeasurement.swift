import Foundation
import CADCore

public struct SelectionAngleMeasurement: Codable, Sendable, Hashable {
    public var first: SelectionMeasurementPoint
    public var second: SelectionMeasurementPoint
    public var firstDirection: Vector3D
    public var secondDirection: Vector3D
    public var angleRadians: Double

    public var angleDegrees: Double {
        angleRadians * 180.0 / Double.pi
    }

    public init(
        first: SelectionMeasurementPoint,
        second: SelectionMeasurementPoint,
        tolerance: ModelingTolerance = .standard
    ) throws {
        try tolerance.validate()
        let firstDirection = try Self.direction(from: first, tolerance: tolerance)
        let secondDirection = try Self.direction(from: second, tolerance: tolerance)
        let clampedDot = min(max(firstDirection.dot(secondDirection), -1.0), 1.0)
        let angleRadians = acos(clampedDot)
        guard angleRadians.isFinite else {
            throw GeometryError.invalidAngle(angleRadians)
        }
        self.first = first
        self.second = second
        self.firstDirection = firstDirection
        self.secondDirection = secondDirection
        self.angleRadians = angleRadians
    }

    private static func direction(
        from point: SelectionMeasurementPoint,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        if let tangent = point.tangent {
            return try tangent.normalized(tolerance: tolerance.distance)
        }
        if let normal = point.normal {
            return try normal.normalized(tolerance: tolerance.distance)
        }
        throw FeatureEvaluationError.unsupportedOperation(
            "Selection angle measurement requires a tangent or normal direction."
        )
    }
}
