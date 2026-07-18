import CADCore

public struct FaceLoopOffsetFeature: Codable, Hashable, Sendable {
    public var target: FaceLoopOffsetTargetReference
    public var face: StableSubshapeReference
    public var distance: CADExpression

    public init(
        target: FaceLoopOffsetTargetReference,
        face: StableSubshapeReference,
        distance: CADExpression
    ) {
        self.target = target
        self.face = face
        self.distance = distance
    }

    public func validate() throws {
        try target.validate()
        try face.validate()
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case face
        case distance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .face, .distance], in: decoder)
        target = try container.decode(FaceLoopOffsetTargetReference.self, forKey: .target)
        face = try container.decode(StableSubshapeReference.self, forKey: .face)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(face, forKey: .face)
        try container.encode(distance, forKey: .distance)
    }
}

public struct FaceLoopOffsetTargetReference: Codable, Hashable, Sendable {
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
