import CADCore

public struct G2BlendFeature: Codable, Hashable, Sendable {
    public let target: G2BlendTargetReference
    public let edges: [StableSubshapeReference]
    public let distance: CADExpression

    public init(
        target: G2BlendTargetReference,
        edges: [StableSubshapeReference],
        distance: CADExpression
    ) {
        self.target = target
        self.edges = edges
        self.distance = distance
    }

    public func validate() throws {
        try target.validate()
        guard edges.isEmpty == false,
              Set(edges).count == edges.count else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "G2 blend requires unique edge selections."
            )
        }
        for edge in edges {
            try edge.validate()
        }
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case edges
        case distance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .distance], in: decoder)
        target = try container.decode(G2BlendTargetReference.self, forKey: .target)
        edges = try container.decode([StableSubshapeReference].self, forKey: .edges)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edges, forKey: .edges)
        try container.encode(distance, forKey: .distance)
    }
}
