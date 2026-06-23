import CADCore
import CADIR

public struct CADAgentAddExtrudeCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var extrude: ExtrudeFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case extrude
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, extrude: ExtrudeFeature) {
        self.featureID = featureID
        self.name = name
        self.extrude = extrude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .extrude], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        extrude = try container.decode(ExtrudeFeature.self, forKey: .extrude)
    }
}
