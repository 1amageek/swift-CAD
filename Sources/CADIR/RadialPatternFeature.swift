import CADCore

public struct RadialPatternFeature: Codable, Hashable, Sendable {
    public let target: PatternTargetReference
    public let axisOrigin: Point3D
    public let axisDirection: Vector3D
    public let angularSpacing: CADExpression
    public let count: Int

    public init(
        target: PatternTargetReference,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        angularSpacing: CADExpression,
        count: Int
    ) {
        self.target = target
        self.axisOrigin = axisOrigin
        self.axisDirection = axisDirection
        self.angularSpacing = angularSpacing
        self.count = count
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try target.validate()
        try axisOrigin.validate()
        try axisDirection.validate()
        guard axisDirection.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(axisDirection.length)
        }
        try angularSpacing.validateLiteralQuantities()
        guard count >= 2, count <= 1_000 else {
            throw KernelError(
                phase: .validation,
                code: count > 1_000 ? .resourceLimitExceeded : .invalidInput,
                tolerance: tolerance,
                message: "Radial pattern count must be between 2 and 1000."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case axisOrigin
        case axisDirection
        case angularSpacing
        case count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .axisOrigin, .axisDirection, .angularSpacing, .count],
            in: decoder
        )
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        axisOrigin = try container.decode(Point3D.self, forKey: .axisOrigin)
        axisDirection = try container.decode(Vector3D.self, forKey: .axisDirection)
        angularSpacing = try container.decode(CADExpression.self, forKey: .angularSpacing)
        count = try container.decode(Int.self, forKey: .count)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(axisOrigin, forKey: .axisOrigin)
        try container.encode(axisDirection, forKey: .axisDirection)
        try container.encode(angularSpacing, forKey: .angularSpacing)
        try container.encode(count, forKey: .count)
    }
}
