import CADCore

public struct MirrorFeature: Codable, Hashable, Sendable {
    public let target: PatternTargetReference
    public let planeOrigin: Point3D
    public let planeNormal: Vector3D

    public init(
        target: PatternTargetReference,
        planeOrigin: Point3D,
        planeNormal: Vector3D
    ) {
        self.target = target
        self.planeOrigin = planeOrigin
        self.planeNormal = planeNormal
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try target.validate()
        try planeOrigin.validate()
        try planeNormal.validate()
        guard planeNormal.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(planeNormal.length)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case planeOrigin
        case planeNormal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .planeOrigin, .planeNormal],
            in: decoder
        )
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        planeOrigin = try container.decode(Point3D.self, forKey: .planeOrigin)
        planeNormal = try container.decode(Vector3D.self, forKey: .planeNormal)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(planeOrigin, forKey: .planeOrigin)
        try container.encode(planeNormal, forKey: .planeNormal)
    }
}
