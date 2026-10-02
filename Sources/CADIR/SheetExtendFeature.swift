import CADCore

/// Extend Sheet: open edges of a sheet carried on by `distance` in the chosen shape. Modifying,
/// the extensions join the sheet; otherwise they form a sheet of their own beside it, the sheet
/// kept as it was.
public struct SheetExtendFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var edges: [StableSubshapeReference]
    public var distance: CADExpression
    public var shape: SheetExtensionShape
    public var modifies: Bool

    public init(
        target: PatternTargetReference, edges: [StableSubshapeReference], distance: CADExpression,
        shape: SheetExtensionShape = .natural, modifies: Bool = true
    ) {
        self.target = target
        self.edges = edges
        self.distance = distance
        self.shape = shape
        self.modifies = modifies
    }

    public func validate() throws {
        try target.validate()
        guard edges.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Extend Sheet requires at least one edge.")
        }
        var seen = Set<StableSubshapeReference>()
        for edge in edges {
            try edge.validate()
            guard seen.insert(edge).inserted else {
                throw FeatureEvaluationError.invalidGraph("Extend Sheet edges must be unique.")
            }
        }
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target, edges, distance, shape, modifies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .distance, .shape, .modifies], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        edges = try container.decode([StableSubshapeReference].self, forKey: .edges)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        shape = try container.decode(SheetExtensionShape.self, forKey: .shape)
        modifies = try container.decode(Bool.self, forKey: .modifies)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edges, forKey: .edges)
        try container.encode(distance, forKey: .distance)
        try container.encode(shape, forKey: .shape)
        try container.encode(modifies, forKey: .modifies)
    }

    /// The inputs the feature reads: its target, consumed when the extensions join it.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: target.featureID, role: modifies ? .target : .body)]
    }
}

/// How an extended sheet carries on past its edge.
public enum SheetExtensionShape: String, Codable, Hashable, Sendable, CaseIterable {
    /// The sheet's own surface continued.
    case natural
    /// Straight on along the sheet's tangent across the edge.
    case linear
    /// The sheet's stretch before the edge mirrored across it, as Extend Curve mirrors a curve's
    /// end: tangent kept, curvature mirrored.
    case reflective
    /// On from the edge matching the sheet's tangent and curvature across it, the curvature
    /// fading to none at the far end (decided 2026-10-02).
    case soft
}
