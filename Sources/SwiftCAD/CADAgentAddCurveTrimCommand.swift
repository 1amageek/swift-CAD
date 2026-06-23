import CADCore
import CADIR

public struct CADAgentAddCurveTrimCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var curveTrim: CurveTrimFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case curveTrim
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, curveTrim: CurveTrimFeature) {
        self.featureID = featureID
        self.name = name
        self.curveTrim = curveTrim
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .curveTrim], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        curveTrim = try container.decode(CurveTrimFeature.self, forKey: .curveTrim)
    }
}
