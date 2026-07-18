import CADCore

public struct GridPatternFeature: Codable, Hashable, Sendable {
    public let target: PatternTargetReference
    public let firstDirection: Vector3D
    public let firstSpacing: CADExpression
    public let firstCount: Int
    public let secondDirection: Vector3D
    public let secondSpacing: CADExpression
    public let secondCount: Int

    public init(
        target: PatternTargetReference,
        firstDirection: Vector3D,
        firstSpacing: CADExpression,
        firstCount: Int,
        secondDirection: Vector3D,
        secondSpacing: CADExpression,
        secondCount: Int
    ) {
        self.target = target
        self.firstDirection = firstDirection
        self.firstSpacing = firstSpacing
        self.firstCount = firstCount
        self.secondDirection = secondDirection
        self.secondSpacing = secondSpacing
        self.secondCount = secondCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try target.validate()
        try firstDirection.validate()
        try secondDirection.validate()
        guard firstDirection.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(firstDirection.length)
        }
        guard secondDirection.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(secondDirection.length)
        }
        let crossLength = firstDirection.cross(secondDirection).length
        let scale = firstDirection.length * secondDirection.length
        guard crossLength > tolerance.angle * scale else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Grid pattern directions must be nonparallel."
            )
        }
        try firstSpacing.validateLiteralQuantities()
        try secondSpacing.validateLiteralQuantities()
        guard firstCount >= 2, secondCount >= 2 else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Grid pattern counts must each be at least two."
            )
        }
        let product = firstCount.multipliedReportingOverflow(by: secondCount)
        guard product.overflow == false, product.partialValue <= 1_000 else {
            throw KernelError(
                phase: .validation,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Grid pattern supports at most 1000 instances."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case firstDirection
        case firstSpacing
        case firstCount
        case secondDirection
        case secondSpacing
        case secondCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .target,
                .firstDirection,
                .firstSpacing,
                .firstCount,
                .secondDirection,
                .secondSpacing,
                .secondCount,
            ],
            in: decoder
        )
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        firstDirection = try container.decode(Vector3D.self, forKey: .firstDirection)
        firstSpacing = try container.decode(CADExpression.self, forKey: .firstSpacing)
        firstCount = try container.decode(Int.self, forKey: .firstCount)
        secondDirection = try container.decode(Vector3D.self, forKey: .secondDirection)
        secondSpacing = try container.decode(CADExpression.self, forKey: .secondSpacing)
        secondCount = try container.decode(Int.self, forKey: .secondCount)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(firstDirection, forKey: .firstDirection)
        try container.encode(firstSpacing, forKey: .firstSpacing)
        try container.encode(firstCount, forKey: .firstCount)
        try container.encode(secondDirection, forKey: .secondDirection)
        try container.encode(secondSpacing, forKey: .secondSpacing)
        try container.encode(secondCount, forKey: .secondCount)
    }
}
