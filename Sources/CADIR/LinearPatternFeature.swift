import CADCore

public struct LinearPatternFeature: Codable, Hashable, Sendable {
    public let target: PatternTargetReference
    public let direction: Vector3D
    public let spacing: CADExpression
    public let count: Int

    public init(
        target: PatternTargetReference,
        direction: Vector3D,
        spacing: CADExpression,
        count: Int
    ) {
        self.target = target
        self.direction = direction
        self.spacing = spacing
        self.count = count
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try target.validate()
        try direction.validate()
        guard direction.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(direction.length)
        }
        try spacing.validateLiteralQuantities()
        guard count >= 2, count <= 1_000 else {
            throw KernelError(
                phase: .validation,
                code: count > 1_000 ? .resourceLimitExceeded : .invalidInput,
                tolerance: tolerance,
                message: "Linear pattern count must be between 2 and 1000."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case direction
        case spacing
        case count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .direction, .spacing, .count], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        direction = try container.decode(Vector3D.self, forKey: .direction)
        spacing = try container.decode(CADExpression.self, forKey: .spacing)
        count = try container.decode(Int.self, forKey: .count)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(direction, forKey: .direction)
        try container.encode(spacing, forKey: .spacing)
        try container.encode(count, forKey: .count)
    }
}
