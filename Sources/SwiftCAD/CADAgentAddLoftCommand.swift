import CADCore
import CADIR

public struct CADAgentAddLoftCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var loft: LoftFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case loft
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, loft: LoftFeature) {
        self.featureID = featureID
        self.name = name
        self.loft = loft
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .loft], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        loft = try container.decode(LoftFeature.self, forKey: .loft)
    }
}
