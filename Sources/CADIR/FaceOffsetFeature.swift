import CADCore

public struct FaceOffsetFeature: Codable, Hashable, Sendable {
    public let target: FaceOffsetTargetReference
    public let face: StableSubshapeReference
    public let distance: CADExpression

    public init(
        target: FaceOffsetTargetReference,
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
        target = try container.decode(FaceOffsetTargetReference.self, forKey: .target)
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
