import CADCore

public enum CADCommand: Hashable, Sendable {
    case appendFeature(FeatureRequest)
    case replaceFeature(FeatureRequest)
    case upsertParameter(Parameter)
    case addSelectionDimension(SelectionDimension)
    case suppressFeature(featureID: FeatureID, suppressed: Bool)
    case removeFeature(FeatureID)
    case setDocumentAttribute(DocumentAttribute)
    case removeDocumentAttribute(DocumentAttributeID)

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case appendFeature
        case replaceFeature
        case upsertParameter
        case addSelectionDimension
        case suppressFeature
        case removeFeature
        case setDocumentAttribute
        case removeDocumentAttribute
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case appendFeature
        case replaceFeature
        case addSelectionDimension
        case upsertParameter
        case suppressFeature
        case removeFeature
        case setDocumentAttribute
        case removeDocumentAttribute
    }
#endif

#if !hasFeature(Embedded)
    private struct SuppressFeaturePayload: Codable, Hashable, Sendable {
        let featureID: FeatureID
        let suppressed: Bool
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .appendFeature:
            try container.validateOnlyExpectedKeys([.kind, .appendFeature], in: decoder)
            self = .appendFeature(try container.decode(FeatureRequest.self, forKey: .appendFeature))
        case .replaceFeature:
            try container.validateOnlyExpectedKeys([.kind, .replaceFeature], in: decoder)
            self = .replaceFeature(try container.decode(FeatureRequest.self, forKey: .replaceFeature))
        case .upsertParameter:
            try container.validateOnlyExpectedKeys([.kind, .upsertParameter], in: decoder)
            self = .upsertParameter(try container.decode(Parameter.self, forKey: .upsertParameter))
        case .addSelectionDimension:
            try container.validateOnlyExpectedKeys([.kind, .addSelectionDimension], in: decoder)
            self = .addSelectionDimension(
                try container.decode(SelectionDimension.self, forKey: .addSelectionDimension)
            )
        case .suppressFeature:
            try container.validateOnlyExpectedKeys([.kind, .suppressFeature], in: decoder)
            let payload = try container.decode(SuppressFeaturePayload.self, forKey: .suppressFeature)
            self = .suppressFeature(featureID: payload.featureID, suppressed: payload.suppressed)
        case .setDocumentAttribute:
            try container.validateOnlyExpectedKeys([.kind, .setDocumentAttribute], in: decoder)
            self = .setDocumentAttribute(try container.decode(DocumentAttribute.self, forKey: .setDocumentAttribute))
        case .removeDocumentAttribute:
            try container.validateOnlyExpectedKeys([.kind, .removeDocumentAttribute], in: decoder)
            self = .removeDocumentAttribute(try container.decode(DocumentAttributeID.self, forKey: .removeDocumentAttribute))
        case .removeFeature:
            try container.validateOnlyExpectedKeys([.kind, .removeFeature], in: decoder)
            self = .removeFeature(try container.decode(FeatureID.self, forKey: .removeFeature))
        }
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .appendFeature(request):
            try container.encode(Kind.appendFeature, forKey: .kind)
            try container.encode(request, forKey: .appendFeature)
        case let .replaceFeature(request):
            try container.encode(Kind.replaceFeature, forKey: .kind)
            try container.encode(request, forKey: .replaceFeature)
        case let .upsertParameter(parameter):
            try container.encode(Kind.upsertParameter, forKey: .kind)
            try container.encode(parameter, forKey: .upsertParameter)
        case let .addSelectionDimension(dimension):
            try container.encode(Kind.addSelectionDimension, forKey: .kind)
            try container.encode(dimension, forKey: .addSelectionDimension)
        case let .suppressFeature(featureID, suppressed):
            try container.encode(Kind.suppressFeature, forKey: .kind)
            try container.encode(
                SuppressFeaturePayload(featureID: featureID, suppressed: suppressed),
                forKey: .suppressFeature
            )
        case let .setDocumentAttribute(attribute):
            try container.encode(Kind.setDocumentAttribute, forKey: .kind)
            try container.encode(attribute, forKey: .setDocumentAttribute)
        case let .removeDocumentAttribute(id):
            try container.encode(Kind.removeDocumentAttribute, forKey: .kind)
            try container.encode(id, forKey: .removeDocumentAttribute)
        case let .removeFeature(featureID):
            try container.encode(Kind.removeFeature, forKey: .kind)
            try container.encode(featureID, forKey: .removeFeature)
        }
    }
#endif
}

#if !hasFeature(Embedded)
extension CADCommand: Codable {}
#endif
