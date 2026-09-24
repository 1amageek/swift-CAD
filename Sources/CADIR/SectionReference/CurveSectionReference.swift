import CADCore

public struct CurveSectionReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    private enum CodingKeys: String, CodingKey {
        case featureID
    }

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
    }

    public func validate() throws {}
}
