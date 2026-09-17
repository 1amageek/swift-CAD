import CADCore

public struct FilletFeature: Codable, Hashable, Sendable {
    public let target: FilletTargetReference
    public let edges: [StableSubshapeReference]
    public let radius: CADExpression
    public let allEdges: Bool

    public init(
        target: FilletTargetReference,
        edges: [StableSubshapeReference],
        radius: CADExpression,
        allEdges: Bool = false
    ) {
        self.target = target
        self.edges = edges
        self.radius = radius
        self.allEdges = allEdges
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
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case edges
        case radius
        case allEdges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .radius, .allEdges], in: decoder)
        target = try container.decode(FilletTargetReference.self, forKey: .target)
        edges = try container.decode([StableSubshapeReference].self, forKey: .edges)
        radius = try container.decode(CADExpression.self, forKey: .radius)
        allEdges = try container.decodeIfPresent(Bool.self, forKey: .allEdges) ?? false
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edges, forKey: .edges)
        try container.encode(radius, forKey: .radius)
        if allEdges { try container.encode(true, forKey: .allEdges) }
    }
}
