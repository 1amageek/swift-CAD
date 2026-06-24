import CADCore
import CADIR

public struct CADAgentAddRevolveCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var revolve: RevolveFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case revolve
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, revolve: RevolveFeature) {
        self.featureID = featureID
        self.name = name
        self.revolve = revolve
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .revolve], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        revolve = try container.decode(RevolveFeature.self, forKey: .revolve)
    }
}
