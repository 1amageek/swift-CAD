import CADCore
import CADIR

public struct CADAgentAddFaceDraftCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var faceDraft: FaceDraftFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case faceDraft
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, faceDraft: FaceDraftFeature) {
        self.featureID = featureID
        self.name = name
        self.faceDraft = faceDraft
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .faceDraft], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        faceDraft = try container.decode(FaceDraftFeature.self, forKey: .faceDraft)
    }
}
