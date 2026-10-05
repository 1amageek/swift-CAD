import CADCore

public protocol FeatureIDReference: Codable, Hashable, Sendable {
    var featureID: FeatureID { get }

    init(featureID: FeatureID)
}

public extension FeatureIDReference {
#if !hasFeature(Embedded)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FeatureIDReferenceCodingKey.self)
        try container.validateOnlyExpectedKeys([.featureID], in: decoder)
        self.init(featureID: try container.decode(FeatureID.self, forKey: .featureID))
    }
#endif

#if !hasFeature(Embedded)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FeatureIDReferenceCodingKey.self)
        try container.encode(featureID, forKey: .featureID)
    }
#endif
}

private enum FeatureIDReferenceCodingKey: String, CodingKey {
    case featureID
}
