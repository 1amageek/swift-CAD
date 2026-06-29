import CADCore
import CADIR

public struct CADAgentAddFaceDeleteCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var faceDelete: FaceDeleteFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case faceDelete
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, faceDelete: FaceDeleteFeature) {
        self.featureID = featureID
        self.name = name
        self.faceDelete = faceDelete
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .faceDelete], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        faceDelete = try container.decode(FaceDeleteFeature.self, forKey: .faceDelete)
    }
}
