import CADCore
import CADIR

public struct CADAgentAddCurveOffsetCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var curveOffset: CurveOffsetFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case curveOffset
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, curveOffset: CurveOffsetFeature) {
        self.featureID = featureID
        self.name = name
        self.curveOffset = curveOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .curveOffset], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        curveOffset = try container.decode(CurveOffsetFeature.self, forKey: .curveOffset)
    }
}
