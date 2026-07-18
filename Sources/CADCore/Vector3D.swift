import Foundation

public struct Vector3D: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3D(x: 0.0, y: 0.0, z: 0.0)
    public static let unitX = Vector3D(x: 1.0, y: 0.0, z: 0.0)
    public static let unitY = Vector3D(x: 0.0, y: 1.0, z: 0.0)
    public static let unitZ = Vector3D(x: 0.0, y: 0.0, z: 1.0)

    public var length: Double {
        hypot(hypot(x, y), z)
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }

    public func validate() throws {
        try validateCoordinate(x)
        try validateCoordinate(y)
        try validateCoordinate(z)
    }

    public func validateUnitLength(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try validate()
        let length = self.length
        guard length.isFinite, length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(length)
        }
        guard abs(length - 1.0) <= max(tolerance.distance, tolerance.angle) else {
            throw GeometryError.invalidVectorLength(length)
        }
    }

    public func dot(_ other: Vector3D) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: Vector3D) -> Vector3D {
        Vector3D(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    public func normalized(tolerance: Double) throws -> Vector3D {
        guard tolerance.isFinite, tolerance > 0.0 else {
            throw GeometryError.invalidTolerance(distance: tolerance, angle: tolerance)
        }
        try validate()
        let length = self.length
        guard length.isFinite, length > tolerance else {
            throw GeometryError.invalidVectorLength(length)
        }
        return self / length
    }

    public static prefix func - (value: Vector3D) -> Vector3D {
        Vector3D(x: -value.x, y: -value.y, z: -value.z)
    }

    public static func + (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static func * (lhs: Vector3D, rhs: Double) -> Vector3D {
        Vector3D(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    public static func * (lhs: Double, rhs: Vector3D) -> Vector3D {
        rhs * lhs
    }

    public static func / (lhs: Vector3D, rhs: Double) -> Vector3D {
        Vector3D(x: lhs.x / rhs, y: lhs.y / rhs, z: lhs.z / rhs)
    }
}

private func validateCoordinate(_ value: Double) throws {
    guard value.isFinite else {
        throw GeometryError.invalidCoordinate(value)
    }
}
