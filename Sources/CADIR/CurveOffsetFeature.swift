import CADCore

public struct CurveOffsetFeature: Codable, Hashable, Sendable {
    public var source: CurveOutputReference
    public var distance: CADExpression
    public var planeNormal: Vector3D
    public var side: CurveOffsetSide

    public init(
        source: CurveOutputReference,
        distance: CADExpression,
        planeNormal: Vector3D,
        side: CurveOffsetSide = .left
    ) {
        self.source = source
        self.distance = distance
        self.planeNormal = planeNormal
        self.side = side
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try source.validate()
        try distance.validateLiteralQuantities()
        try planeNormal.validateUnitLength(tolerance: tolerance)
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case distance
        case planeNormal
        case side
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.source, .distance, .planeNormal, .side],
            in: decoder
        )
        source = try container.decode(CurveOutputReference.self, forKey: .source)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        planeNormal = try container.decode(Vector3D.self, forKey: .planeNormal)
        side = try container.decode(CurveOffsetSide.self, forKey: .side)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(distance, forKey: .distance)
        try container.encode(planeNormal, forKey: .planeNormal)
        try container.encode(side, forKey: .side)
    }
}

public enum CurveOffsetSide: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right
}
