import CADCore

/// A rotation by `angle` about the axis through `origin` along `axis`, right-handed.
public struct DirectRotation: Codable, Hashable, Sendable {
    public let origin: Point3D
    public let axis: Vector3D
    public let angle: CADExpression

    public init(origin: Point3D, axis: Vector3D, angle: CADExpression) {
        self.origin = origin
        self.axis = axis
        self.angle = angle
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        try axis.validate()
        guard axis.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(axis.length)
        }
        try angle.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case origin
        case axis
        case angle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.origin, .axis, .angle], in: decoder)
        origin = try container.decode(Point3D.self, forKey: .origin)
        axis = try container.decode(Vector3D.self, forKey: .axis)
        angle = try container.decode(CADExpression.self, forKey: .angle)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encode(axis, forKey: .axis)
        try container.encode(angle, forKey: .angle)
    }
}
