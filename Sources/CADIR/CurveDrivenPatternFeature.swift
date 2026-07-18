import CADCore

public struct CurveDrivenPatternFeature: Codable, Hashable, Sendable {
    public let target: PatternTargetReference
    public let path: CurveDrivenPatternPathReference
    public let anchor: Point3D
    public let referenceDirection: Vector3D
    public let count: Int

    public init(
        target: PatternTargetReference,
        path: CurveDrivenPatternPathReference,
        anchor: Point3D,
        referenceDirection: Vector3D,
        count: Int
    ) {
        self.target = target
        self.path = path
        self.anchor = anchor
        self.referenceDirection = referenceDirection
        self.count = count
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try target.validate()
        try path.validate()
        guard target.featureID != path.featureID else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve-driven pattern target and path must be different features."
            )
        }
        try anchor.validate()
        try referenceDirection.validate()
        guard referenceDirection.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(referenceDirection.length)
        }
        guard count >= 2, count <= 1_000 else {
            throw KernelError(
                phase: .validation,
                code: count > 1_000 ? .resourceLimitExceeded : .invalidInput,
                tolerance: tolerance,
                message: "Curve-driven pattern count must be between 2 and 1000."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case path
        case anchor
        case referenceDirection
        case count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .path, .anchor, .referenceDirection, .count],
            in: decoder
        )
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        path = try container.decode(CurveDrivenPatternPathReference.self, forKey: .path)
        anchor = try container.decode(Point3D.self, forKey: .anchor)
        referenceDirection = try container.decode(Vector3D.self, forKey: .referenceDirection)
        count = try container.decode(Int.self, forKey: .count)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(path, forKey: .path)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(referenceDirection, forKey: .referenceDirection)
        try container.encode(count, forKey: .count)
    }
}
