import CADCore
import CADGeometry
import CADTopology

/// The cross-section a fillet rounds an edge with (Fillet Shell's Shape): a circular `round` of
/// the radius; a `conic` set back as the round of the distance's radius, its fullness the tension
/// (0.5 that round); a `chordal` set back as the circular arc whose chord is the distance, its
/// fullness the tension (0.5 that arc); or a
/// `curvature` (G2) quintic meeting both faces at the distance with zero curvature there, its
/// handles scaled by the tension; or a `full` round tangent to the three faces across a center face
/// between the two selected edges, whose radius those faces fix (half the face's width) and the
/// feature's radius must state.
public enum FilletShape: String, Hashable, Sendable {
    /// The tension a shape takes when none is given: 0.5 (the round, or the chordal arc) for the
    /// conic shapes, 1 for the rest.
    public var defaultTension: Double { self == .conic || self == .chordal ? 0.5 : 1 }

    case round
    case conic
    case chordal
    case curvature
    case full
}

public struct FilletFeature: Hashable, Sendable {
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
    /// Fillet Shell's Attempt to create Y-Blend: where blends meet at a corner patch, the patch is
    /// split into faces meeting in a Y at its middle (the same surface, a better topology).
    public let yBlend: Bool

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
        tangentEdges: Bool = true,
        yBlend: Bool = false
    ) {
        self.tangentEdges = tangentEdges
        self.yBlend = yBlend
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

    /// This fillet with any of its target, edges, radius, Tangent Edges or Y-Blend replaced, its
    /// shape kept.
    public func with(
        target: FilletTargetReference? = nil,
        edges: [StableSubshapeReference]? = nil,
        radius: CADExpression? = nil,
        tangentEdges: Bool? = nil,
        yBlend: Bool? = nil
    ) -> FilletFeature {
        FilletFeature(target: target ?? self.target, edges: edges ?? self.edges, radius: radius ?? self.radius,
                      allEdges: allEdges, shape: shape, tension: tension, endRadius: endRadius, limits: limits,
                      variablePoints: variablePoints, tangentEdges: tangentEdges ?? self.tangentEdges, yBlend: yBlend ?? self.yBlend)
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        func uniqueEdgeCount() throws -> Int {
            for reference in edges {
                try reference.chargeStructuralComparison(using: &execution)
            }
            return try OriginalParameterQueryStorage.set(edges, using: &execution).count
        }
        try target.validate()
        guard (allEdges ? edges.isEmpty : !edges.isEmpty),
              (try uniqueEdgeCount()) == edges.count else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Fillet requires unique explicit edges or an exclusive all-edge selection."
            )
        }
        for edge in edges {
            try execution.consumeWork(1)
            try edge.validate(using: &execution)
        }
        try radius.validateDocumentLiteralQuantities(using: &execution)
        if let endRadius {
            try endRadius.validateDocumentLiteralQuantities(using: &execution)
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
            let positions = try OriginalParameterQueryStorage.map(variablePoints, using: &execution) { value, _ in value.position }
            guard !allEdges, edges.count == 1, shape != .full, limits == nil,
                  try OriginalParameterQueryStorage.allSatisfy(positions, using: &execution,
                    predicate: { value, _ in value.isFinite && value > 0 && value < 1 }),
                  try OriginalParameterQueryStorage.allSatisfy(zip(positions, positions.dropFirst()), using: &execution,
                    predicate: { pair, _ in pair.0 < pair.1 }) else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A fillet's variable points lie in order strictly inside its one edge.")
            }
            for point in variablePoints {
                try execution.consumeWork(1)
                try point.radius.validateDocumentLiteralQuantities(using: &execution)
            }
        }
        if let limits {
            try execution.consumeWork(1); try limits.validate()
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

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
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
        case yBlend
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .radius, .allEdges, .shape, .tension, .endRadius, .limits, .variablePoints, .tangentEdges, .yBlend], in: decoder)
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
        yBlend = try container.decodeIfPresent(Bool.self, forKey: .yBlend) ?? false
        try validate()
    }
#endif

#if !hasFeature(Embedded)
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
        if yBlend { try container.encode(true, forKey: .yBlend) }
    }
#endif
}

#if !hasFeature(Embedded)
extension FilletShape: Codable {}
extension FilletFeature: Codable {}
#endif
