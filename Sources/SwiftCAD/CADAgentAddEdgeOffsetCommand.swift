import CADCore
import CADIR

public struct CADAgentAddEdgeOffsetCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var edgeOffset: EdgeOffsetFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case edgeOffset
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, edgeOffset: EdgeOffsetFeature) {
        self.featureID = featureID
        self.name = name
        self.edgeOffset = edgeOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .edgeOffset], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        edgeOffset = try container.decode(EdgeOffsetFeature.self, forKey: .edgeOffset)
    }
}
