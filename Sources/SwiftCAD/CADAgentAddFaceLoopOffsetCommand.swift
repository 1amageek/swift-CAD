import CADCore
import CADIR

public struct CADAgentAddFaceLoopOffsetCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var faceLoopOffset: FaceLoopOffsetFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case faceLoopOffset
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, faceLoopOffset: FaceLoopOffsetFeature) {
        self.featureID = featureID
        self.name = name
        self.faceLoopOffset = faceLoopOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .faceLoopOffset], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        faceLoopOffset = try container.decode(FaceLoopOffsetFeature.self, forKey: .faceLoopOffset)
    }
}
