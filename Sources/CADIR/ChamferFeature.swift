import CADCore

/// How a chamfer's distance sets where it meets its two faces: `offset` (Plasticity's default) cuts
/// where each face offset inward by the distance meets the other, `distance / sin α` along each
/// face for faces meeting at the interior angle α; `apex` measures the distance along each face
/// from the edge, which keeps the chamfer's border nearer the edge where the faces are not square.
public enum ChamferMode: String, Codable, Hashable, Sendable, CaseIterable {
    case offset
    case apex
}

public struct ChamferFeature: Codable, Hashable, Sendable {
    public let target: ChamferTargetReference
    public let edges: [StableSubshapeReference]
    public let distance: CADExpression
    public let mode: ChamferMode
    /// The chamfer's angle to its reference face, `distance` measured along that face from the edge
    /// and the other contact set by the angle; nil for a symmetric chamfer by `mode`.
    public let angle: CADExpression?
    /// Whether the reference face of an angled chamfer is each edge's second face rather than its
    /// first.
    public let flipped: Bool
    /// The stretch of the one edge the chamfer runs over, closed on its section at each limit
    /// inside the edge; nil for the whole edge.
    public let limits: EdgeBlendLimits?
    /// Fillet Shell's Tangent Edges: whether an edge takes the edges continuing it tangentially.
    public let tangentEdges: Bool

    public init(
        target: ChamferTargetReference,
        edges: [StableSubshapeReference],
        distance: CADExpression,
        mode: ChamferMode = .offset,
        angle: CADExpression? = nil,
        flipped: Bool = false,
        limits: EdgeBlendLimits? = nil,
        tangentEdges: Bool = true
    ) {
        self.tangentEdges = tangentEdges
        self.target = target
        self.edges = edges
        self.distance = distance
        self.mode = mode
        self.angle = angle
        self.flipped = flipped
        self.limits = limits
    }

    /// This chamfer with any of its target, edges, distance or Tangent Edges replaced, its shape kept.
    public func with(
        target: ChamferTargetReference? = nil,
        edges: [StableSubshapeReference]? = nil,
        distance: CADExpression? = nil,
        tangentEdges: Bool? = nil
    ) -> ChamferFeature {
        ChamferFeature(target: target ?? self.target, edges: edges ?? self.edges, distance: distance ?? self.distance,
                       mode: mode, angle: angle, flipped: flipped, limits: limits, tangentEdges: tangentEdges ?? self.tangentEdges)
    }

    public func validate() throws {
        try target.validate()
        guard edges.isEmpty == false,
              Set(edges).count == edges.count else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Chamfer requires unique edge selections."
            )
        }
        for edge in edges {
            try edge.validate()
        }
        try distance.validateLiteralQuantities()
        try angle?.validateLiteralQuantities()
        guard angle != nil || flipped == false else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                              message: "Only an angled chamfer has a reference face to flip.")
        }
        if let limits {
            try limits.validate()
            guard edges.count == 1 else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "Limits bound one chamfer's edge.")
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case edges
        case distance
        case mode
        case angle
        case flipped
        case limits
        case tangentEdges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .distance, .mode, .angle, .flipped, .limits, .tangentEdges], in: decoder)
        target = try container.decode(ChamferTargetReference.self, forKey: .target)
        edges = try container.decode([StableSubshapeReference].self, forKey: .edges)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        mode = try container.decodeIfPresent(ChamferMode.self, forKey: .mode) ?? .offset
        angle = try container.decodeIfPresent(CADExpression.self, forKey: .angle)
        flipped = try container.decodeIfPresent(Bool.self, forKey: .flipped) ?? false
        limits = try container.decodeIfPresent(EdgeBlendLimits.self, forKey: .limits)
        tangentEdges = try container.decodeIfPresent(Bool.self, forKey: .tangentEdges) ?? true
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edges, forKey: .edges)
        try container.encode(distance, forKey: .distance)
        if mode != .offset { try container.encode(mode, forKey: .mode) }
        try container.encodeIfPresent(angle, forKey: .angle)
        if flipped { try container.encode(true, forKey: .flipped) }
        try container.encodeIfPresent(limits, forKey: .limits)
        if tangentEdges == false { try container.encode(false, forKey: .tangentEdges) }
    }
}
