import CADCore
import CADIR

public struct CADAgentAddSweepCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var sweep: SweepFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case sweep
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, sweep: SweepFeature) {
        self.featureID = featureID
        self.name = name
        self.sweep = sweep
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .sweep], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        sweep = try container.decode(SweepFeature.self, forKey: .sweep)
    }
}
