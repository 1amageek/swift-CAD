import CADCore

public struct EdgeMoveTargetReference: Codable, Hashable, Sendable {
    public let featureID: FeatureID

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
