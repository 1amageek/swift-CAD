import CADCore

public struct DirectMoveVector: Codable, Hashable, Sendable {
    public let direction: Vector3D
    public let distance: CADExpression

    public init(direction: Vector3D, distance: CADExpression) {
        self.direction = direction
        self.distance = distance
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try direction.validate()
        guard direction.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(direction.length)
        }
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case distance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.direction, .distance], in: decoder)
        direction = try container.decode(Vector3D.self, forKey: .direction)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(direction, forKey: .direction)
        try container.encode(distance, forKey: .distance)
    }
}
