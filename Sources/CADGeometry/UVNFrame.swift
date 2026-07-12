import CADCore

/// An orthonormal surface frame with parameter directions U, V, and surface normal N.
public struct UVNFrame: Codable, Equatable, Hashable, Sendable {
    public let position: Point3D
    public let u: Vector3D
    public let v: Vector3D
    public let normal: Vector3D

    public init(
        position: Point3D,
        u: Vector3D,
        v: Vector3D,
        normal: Vector3D,
        tolerance: ModelingTolerance = .standard
    ) throws {
        try tolerance.validate()
        try position.validate()
        try u.validateUnitLength(tolerance: tolerance)
        try v.validateUnitLength(tolerance: tolerance)
        try normal.validateUnitLength(tolerance: tolerance)
        guard abs(u.dot(v)) <= tolerance.angle,
              abs(u.dot(normal)) <= tolerance.angle,
              abs(v.dot(normal)) <= tolerance.angle,
              u.cross(v).dot(normal) > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                message: "UVN frame vectors must form a right-handed orthonormal frame."
            )
        }
        self.position = position
        self.u = u
        self.v = v
        self.normal = normal
    }
}
