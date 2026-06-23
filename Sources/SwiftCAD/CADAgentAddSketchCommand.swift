import CADCore
import CADIR

public struct CADAgentAddSketchCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var sketch: Sketch

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case sketch
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, sketch: Sketch) {
        self.featureID = featureID
        self.name = name
        self.sketch = sketch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .sketch], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        sketch = try container.decode(Sketch.self, forKey: .sketch)
    }
}
