import CADCore
import CADGeometry
import CADTopology

public struct G2BlendFeature: Hashable, Sendable {
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
        guard edges.isEmpty == false,
              (try uniqueEdgeCount()) == edges.count else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "G2 blend requires unique edge selections."
            )
        }
        for edge in edges {
            try execution.consumeWork(1)
            try edge.validate(using: &execution)
        }
        try distance.validateDocumentLiteralQuantities(using: &execution)

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case edges
        case distance
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edges, .distance], in: decoder)
        target = try container.decode(G2BlendTargetReference.self, forKey: .target)
        edges = try container.decode([StableSubshapeReference].self, forKey: .edges)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edges, forKey: .edges)
        try container.encode(distance, forKey: .distance)
    }
#endif
}

#if !hasFeature(Embedded)
extension G2BlendFeature: Codable {}
#endif
