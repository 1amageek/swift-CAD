import CADCore
import CADTopology

/// Edges offset across faces (Offset Edge): each chosen edge is offset by `distance` over the one
/// support face it bounds — a chain across a top and a slope runs over both — the offsets of
/// neighbouring edges joined as `gapFill` says, and imprinted on the faces; a chain that stops
/// short of a face's boundary carries on to it. Symmetric offsets also go over the face on the
/// other side of each edge.
public struct EdgeOffsetFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var edges: [StableSubshapeReference]
    public var supportFaces: [StableSubshapeReference]
    public var distance: CADExpression
    public var isSymmetric: Bool
    public var gapFill: OffsetGapFill

    public init(
        target: PatternTargetReference,
        edges: [StableSubshapeReference],
        supportFaces: [StableSubshapeReference],
        distance: CADExpression,
        isSymmetric: Bool = false,
        gapFill: OffsetGapFill = .round
    ) {
        self.target = target
        self.edges = edges
        self.supportFaces = supportFaces
        self.distance = distance
        self.isSymmetric = isSymmetric
        self.gapFill = gapFill
    }

    public func validate() throws {
        try target.validate()
        guard edges.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Offset Edge needs at least one edge.")
        }
        for edge in edges { try edge.validate() }
        guard Set(edges).count == edges.count else {
            throw FeatureEvaluationError.invalidGraph("Offset Edge's edges must be distinct.")
        }
        guard supportFaces.isEmpty == false, Set(supportFaces).count == supportFaces.count else {
            throw FeatureEvaluationError.invalidGraph("Offset Edge needs distinct support faces.")
        }
        for face in supportFaces { try face.validate() }
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target, edges, supportFaces, distance, isSymmetric, gapFill
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .supportFaces, .distance, .isSymmetric, .gapFill], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        edges = try container.decode([StableSubshapeReference].self, forKey: .edges)
        supportFaces = try container.decode([StableSubshapeReference].self, forKey: .supportFaces)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        isSymmetric = try container.decode(Bool.self, forKey: .isSymmetric)
        gapFill = try container.decode(OffsetGapFill.self, forKey: .gapFill)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edges, forKey: .edges)
        try container.encode(supportFaces, forKey: .supportFaces)
        try container.encode(distance, forKey: .distance)
        try container.encode(isSymmetric, forKey: .isSymmetric)
        try container.encode(gapFill, forKey: .gapFill)
    }
}

/// How the offsets of two edges meeting at a corner are joined where they part.
public enum OffsetGapFill: String, Codable, Hashable, Sendable {
    /// An arc around the corner at the offset distance.
    case round
    /// Straight lines carrying each offset on until they meet, a sharp corner of edges of their own
    /// (Plasticity's Linear: "edges may be fragmented").
    case linear
    /// Each offset itself carried on until the two meet, keeping the edges continuous (Plasticity's
    /// Natural).
    case natural
}
