import CADCore
import CADIR

public struct CADAgentAddCurveEditCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var curveEdit: CurveEditFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case curveEdit
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, curveEdit: CurveEditFeature) {
        self.featureID = featureID
        self.name = name
        self.curveEdit = curveEdit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .curveEdit], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        curveEdit = try container.decode(CurveEditFeature.self, forKey: .curveEdit)
    }
}
