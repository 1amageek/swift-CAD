import CADCore
import CADIR

public struct CADAgentAddFaceKnifeCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var faceKnife: FaceKnifeFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case faceKnife
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, faceKnife: FaceKnifeFeature) {
        self.featureID = featureID
        self.name = name
        self.faceKnife = faceKnife
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .faceKnife], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        faceKnife = try container.decode(FaceKnifeFeature.self, forKey: .faceKnife)
    }
}
