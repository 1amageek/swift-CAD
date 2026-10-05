import CADCore

public enum DocumentObjectTarget: Hashable, Sendable {
    case document
    case feature(FeatureID)
    case parameter(ParameterID)
    case attribute(DocumentAttributeID)

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case kind, featureID, parameterID, attributeID }
    private enum Kind: String, Codable { case document, feature, parameter, attribute }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .document:
            try c.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .document
        case .feature:
            try c.validateOnlyExpectedKeys([.kind, .featureID], in: decoder)
            self = .feature(try c.decode(FeatureID.self, forKey: .featureID))
        case .parameter:
            try c.validateOnlyExpectedKeys([.kind, .parameterID], in: decoder)
            self = .parameter(try c.decode(ParameterID.self, forKey: .parameterID))
        case .attribute:
            try c.validateOnlyExpectedKeys([.kind, .attributeID], in: decoder)
            self = .attribute(try c.decode(DocumentAttributeID.self, forKey: .attributeID))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .document: try c.encode(Kind.document, forKey: .kind)
        case .feature(let id): try c.encode(Kind.feature, forKey: .kind); try c.encode(id, forKey: .featureID)
        case .parameter(let id): try c.encode(Kind.parameter, forKey: .kind); try c.encode(id, forKey: .parameterID)
        case .attribute(let id): try c.encode(Kind.attribute, forKey: .kind); try c.encode(id, forKey: .attributeID)
        }
    }
    #endif
}

#if !hasFeature(Embedded)
extension DocumentObjectTarget: Codable {}
#endif
