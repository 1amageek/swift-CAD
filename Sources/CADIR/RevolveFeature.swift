import CADCore

public struct RevolveFeature: Codable, Hashable, Sendable {
    public var profile: ProfileReference
    public var axis: RevolveAxis
    public var angle: CADExpression
    public var operation: SolidOperation

    public init(
        profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree)),
        operation: SolidOperation = .newBody
    ) {
        self.profile = profile
        self.axis = axis
        self.angle = angle
        self.operation = operation
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try profile.validate()
        try axis.validate(tolerance: tolerance)
        try angle.validateLiteralQuantities()
    }
}

public struct RevolveAxis: Codable, Hashable, Sendable {
    public var origin: Point3D
    public var direction: Vector3D

    public init(origin: Point3D, direction: Vector3D) {
        self.origin = origin
        self.direction = direction
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        _ = try direction.normalized(tolerance: tolerance.distance)
    }

    public func normalizedDirection(tolerance: ModelingTolerance) throws -> Vector3D {
        try direction.normalized(tolerance: tolerance.distance)
    }
}
