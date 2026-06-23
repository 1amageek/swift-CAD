import CADCore
import CADIR

public struct CADAgentAddPolySplineCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var polySpline: PolySplineFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case polySpline
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, polySpline: PolySplineFeature) {
        self.featureID = featureID
        self.name = name
        self.polySpline = polySpline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .polySpline], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        polySpline = try container.decode(PolySplineFeature.self, forKey: .polySpline)
    }
}
