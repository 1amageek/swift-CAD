import CADCore

/// Remove Fillets From Shell: every fillet of a solid no wider than `maximumRadius` (any, when
/// nil) and of the chosen convexity is taken out, and the faces it joined grow to meet where it
/// was.
public struct RemoveFilletsFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var maximumRadius: CADExpression?
    public var convexity: FilletConvexity

    public init(target: PatternTargetReference, maximumRadius: CADExpression? = nil, convexity: FilletConvexity = .any) {
        self.target = target
        self.maximumRadius = maximumRadius
        self.convexity = convexity
    }

    public func validate() throws {
        try target.validate()
        try maximumRadius?.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target, maximumRadius, convexity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .maximumRadius, .convexity], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        maximumRadius = try container.decodeIfPresent(CADExpression.self, forKey: .maximumRadius)
        convexity = try container.decode(FilletConvexity.self, forKey: .convexity)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(maximumRadius, forKey: .maximumRadius)
        try container.encode(convexity, forKey: .convexity)
    }
}

/// Which fillets Remove Fillets takes: any, those rounding an outside edge (whose centre lies in
/// the material), or those filling an inside corner.
public enum FilletConvexity: String, Codable, Hashable, Sendable, CaseIterable {
    case any
    case convex
    case concave
}
