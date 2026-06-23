import CADCore
import CADIR

public struct CADAgentAddBridgeCurveCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var bridgeCurve: BridgeCurveFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case bridgeCurve
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, bridgeCurve: BridgeCurveFeature) {
        self.featureID = featureID
        self.name = name
        self.bridgeCurve = bridgeCurve
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .bridgeCurve], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        bridgeCurve = try container.decode(BridgeCurveFeature.self, forKey: .bridgeCurve)
    }
}
