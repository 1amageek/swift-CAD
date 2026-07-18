import CADCore

public struct EdgeOffsetFeature: Codable, Hashable, Sendable {
    public var target: EdgeOffsetTargetReference
    public var edge: StableSubshapeReference
    public var supportFace: StableSubshapeReference
    public var distance: CADExpression
    public var isSymmetric: Bool

    public init(
        target: EdgeOffsetTargetReference,
        edge: StableSubshapeReference,
        supportFace: StableSubshapeReference,
        distance: CADExpression,
        isSymmetric: Bool = false
    ) {
        self.target = target
        self.edge = edge
        self.supportFace = supportFace
        self.distance = distance
        self.isSymmetric = isSymmetric
    }

    public func validate() throws {
        try target.validate()
        try edge.validate()
        try supportFace.validate()
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case edge
        case supportFace
        case distance
        case isSymmetric
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .edge, .supportFace, .distance, .isSymmetric],
            in: decoder
        )
        target = try container.decode(EdgeOffsetTargetReference.self, forKey: .target)
        edge = try container.decode(StableSubshapeReference.self, forKey: .edge)
        supportFace = try container.decode(StableSubshapeReference.self, forKey: .supportFace)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        isSymmetric = try container.decode(Bool.self, forKey: .isSymmetric)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edge, forKey: .edge)
        try container.encode(supportFace, forKey: .supportFace)
        try container.encode(distance, forKey: .distance)
        try container.encode(isSymmetric, forKey: .isSymmetric)
    }
}

public struct EdgeOffsetTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}

    private enum CodingKeys: String, CodingKey {
        case featureID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
    }
}
