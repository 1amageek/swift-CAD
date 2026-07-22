import CADCore

public struct CurveExtendFeature: Codable, Hashable, Sendable {
    public let source: CurveOutputReference
    public let end: CurveExtensionEnd
    public let distance: CADExpression

    public init(
        source: CurveOutputReference,
        end: CurveExtensionEnd,
        distance: CADExpression
    ) {
        self.source = source
        self.end = end
        self.distance = distance
    }

    public func validate() throws {
        try source.validate()
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case end
        case distance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .end, .distance], in: decoder)
        source = try container.decode(CurveOutputReference.self, forKey: .source)
        end = try container.decode(CurveExtensionEnd.self, forKey: .end)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(end, forKey: .end)
        try container.encode(distance, forKey: .distance)
    }
}
