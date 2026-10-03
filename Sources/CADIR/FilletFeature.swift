import CADCore

/// The cross-section a fillet rounds an edge with (Fillet Shell's Shape): a circular `round` of
/// the radius; a `conic` set back as the round of the distance's radius, its fullness the tension
/// (0.5 that round); a `chordal` set back as the circular arc whose chord is the distance, its
/// fullness the tension (0.5 that arc); or a
/// `curvature` (G2) quintic meeting both faces at the distance with zero curvature there, its
/// handles scaled by the tension; or a `full` round tangent to the three faces across a center face
/// between the two selected edges, whose radius those faces fix (half the face's width) and the
/// feature's radius must state.
public enum FilletShape: String, Codable, Hashable, Sendable {
    /// The tension a shape takes when none is given: 0.5 (the round, or the chordal arc) for the
    /// conic shapes, 1 for the rest.
    public var defaultTension: Double { self == .conic || self == .chordal ? 0.5 : 1 }

    case round
    case conic
    case chordal
    case curvature
    case full
}

public struct FilletFeature: Codable, Hashable, Sendable {
    public let target: FilletTargetReference
    public let edges: [StableSubshapeReference]
    /// The radius of a round fillet, the distance of the other shapes.
    public let radius: CADExpression
    public let allEdges: Bool
    public let shape: FilletShape
    /// A conic's rho in (0, 1), or the scale of a curvature fillet's handles; 1 otherwise.
    public let tension: Double
    /// A variable fillet's radius (or distance) at its edge's end, `radius` being the one at its
    /// start, varying linearly between when there are no variable points (along the natural cubic
    /// spline through them when there are); nil for a constant one.
    public let endRadius: CADExpression?
    /// The stretch of the edge the fillet runs over; nil for all of it.
    public let limits: EdgeBlendLimits?
    /// The radii at points between the edge's ends, in order along it; empty for none.
    public let variablePoints: [FilletVariablePoint]
    /// Fillet Shell's Tangent Edges: whether an edge takes the edges continuing it tangentially.
    public let tangentEdges: Bool

    public init(
        target: FilletTargetReference,
        edges: [StableSubshapeReference],
        radius: CADExpression,
        allEdges: Bool = false,
        shape: FilletShape = .round,
        tension: Double? = nil,
        endRadius: CADExpression? = nil,
        limits: EdgeBlendLimits? = nil,
        variablePoints: [FilletVariablePoint] = [],
        tangentEdges: Bool = true
    ) {
        self.tangentEdges = tangentEdges
        self.limits = limits
        self.variablePoints = variablePoints
        self.target = target
        self.edges = edges
        self.radius = radius
        self.allEdges = allEdges
        self.shape = shape
        self.tension = tension ?? shape.defaultTension
        self.endRadius = endRadius
    }

    /// This fillet with any of its target, edges, radius or Tangent Edges replaced, its shape kept.
    public func with(
        target: FilletTargetReference? = nil,
        edges: [StableSubshapeReference]? = nil,
        radius: CADExpression? = nil,
        tangentEdges: Bool? = nil
    ) -> FilletFeature {
        FilletFeature(target: target ?? self.target, edges: edges ?? self.edges, radius: radius ?? self.radius,
                      allEdges: allEdges, shape: shape, tension: tension, endRadius: endRadius, limits: limits,
                      variablePoints: variablePoints, tangentEdges: tangentEdges ?? self.tangentEdges)
    }

    public func validate() throws {
        try target.validate()
        guard (allEdges ? edges.isEmpty : !edges.isEmpty),
              Set(edges).count == edges.count else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Fillet requires unique explicit edges or an exclusive all-edge selection."
            )
        }
        for edge in edges {
            try edge.validate()
        }
        try radius.validateLiteralQuantities()
        if let endRadius {
            try endRadius.validateLiteralQuantities()
            guard !allEdges, edges.count == 1, shape != .full else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A variable fillet rounds one edge, not a full round.")
            }
        }
        switch shape {
        case .round, .full:
            guard tension == 1 else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A round or full fillet takes no tension.")
            }
        case .conic, .chordal:
            guard tension.isFinite, tension > 0, tension < 1 else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A conic or chordal fillet's tension lies strictly between 0 and 1.")
            }
        case .curvature:
            guard tension.isFinite, tension > 0, tension <= 1.5 else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A curvature fillet's tension lies in (0, 1.5].")
            }
        }
        if variablePoints.isEmpty == false {
            let positions = variablePoints.map(\.position)
            guard !allEdges, edges.count == 1, shape != .full, limits == nil,
                  positions.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1 }), zip(positions, positions.dropFirst()).allSatisfy({ $0 < $1 }) else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A fillet's variable points lie in order strictly inside its one edge.")
            }
            for point in variablePoints { try point.radius.validateLiteralQuantities() }
        }
        if let limits {
            try limits.validate()
            guard !allEdges, edges.count == 1, shape != .full, endRadius == nil else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "Limits bound one constant fillet's edge.")
            }
        }
        guard shape == .round || (!allEdges && (shape == .full ? edges.count >= 2 && edges.count % 2 == 0 : edges.isEmpty == false)) else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                              message: shape == .full
                                ? "A full fillet rounds across a face between each pair of edges, two by two."
                                : "A conic, chordal or curvature fillet rounds one edge.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case edges
        case radius
        case allEdges
        case shape
        case tension
        case endRadius
        case limits
        case variablePoints
        case tangentEdges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .radius, .allEdges, .shape, .tension, .endRadius, .limits, .variablePoints, .tangentEdges], in: decoder)
        target = try container.decode(FilletTargetReference.self, forKey: .target)
        edges = try container.decode([StableSubshapeReference].self, forKey: .edges)
        radius = try container.decode(CADExpression.self, forKey: .radius)
        allEdges = try container.decodeIfPresent(Bool.self, forKey: .allEdges) ?? false
        shape = try container.decodeIfPresent(FilletShape.self, forKey: .shape) ?? .round
        tension = try container.decodeIfPresent(Double.self, forKey: .tension) ?? shape.defaultTension
        endRadius = try container.decodeIfPresent(CADExpression.self, forKey: .endRadius)
        limits = try container.decodeIfPresent(EdgeBlendLimits.self, forKey: .limits)
        variablePoints = try container.decodeIfPresent([FilletVariablePoint].self, forKey: .variablePoints) ?? []
        tangentEdges = try container.decodeIfPresent(Bool.self, forKey: .tangentEdges) ?? true
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edges, forKey: .edges)
        try container.encode(radius, forKey: .radius)
        if allEdges { try container.encode(true, forKey: .allEdges) }
        if shape != .round {
            try container.encode(shape, forKey: .shape)
            try container.encode(tension, forKey: .tension)
        }
        try container.encodeIfPresent(endRadius, forKey: .endRadius)
        try container.encodeIfPresent(limits, forKey: .limits)
        if variablePoints.isEmpty == false { try container.encode(variablePoints, forKey: .variablePoints) }
        if tangentEdges == false { try container.encode(false, forKey: .tangentEdges) }
    }
}
