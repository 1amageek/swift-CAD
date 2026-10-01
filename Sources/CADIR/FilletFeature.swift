import CADCore

/// The cross-section a fillet rounds an edge with (Fillet Shell's Shape): a circular `round` of
/// the radius; a `conic` meeting both faces at the distance from the edge, its sharpness the
/// tension (the conic's rho); a `chordal` circular arc whose chord is the distance; or a
/// `curvature` (G2) quintic meeting both faces at the distance with zero curvature there, its
/// handles scaled by the tension; or a `full` round tangent to the three faces across a center face
/// between the two selected edges, its size set by those faces (the radius is not used).
public enum FilletShape: String, Codable, Hashable, Sendable {
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

    public init(
        target: FilletTargetReference,
        edges: [StableSubshapeReference],
        radius: CADExpression,
        allEdges: Bool = false,
        shape: FilletShape = .round,
        tension: Double? = nil
    ) {
        self.target = target
        self.edges = edges
        self.radius = radius
        self.allEdges = allEdges
        self.shape = shape
        self.tension = tension ?? (shape == .conic ? 0.5 : 1)
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
        switch shape {
        case .round, .chordal, .full:
            guard tension == 1 else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A round, chordal or full fillet takes no tension.")
            }
        case .conic:
            guard tension.isFinite, tension > 0, tension < 1 else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A conic fillet's tension (rho) lies strictly between 0 and 1.")
            }
        case .curvature:
            guard tension.isFinite, tension > 0, tension <= 1.5 else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                                  message: "A curvature fillet's tension lies in (0, 1.5].")
            }
        }
        guard shape == .round || (!allEdges && edges.count == (shape == .full ? 2 : 1)) else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                              message: shape == .full
                                ? "A full fillet rounds across the face between two edges."
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .radius, .allEdges, .shape, .tension], in: decoder)
        target = try container.decode(FilletTargetReference.self, forKey: .target)
        edges = try container.decode([StableSubshapeReference].self, forKey: .edges)
        radius = try container.decode(CADExpression.self, forKey: .radius)
        allEdges = try container.decodeIfPresent(Bool.self, forKey: .allEdges) ?? false
        shape = try container.decodeIfPresent(FilletShape.self, forKey: .shape) ?? .round
        tension = try container.decodeIfPresent(Double.self, forKey: .tension) ?? (shape == .conic ? 0.5 : 1)
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
    }
}
