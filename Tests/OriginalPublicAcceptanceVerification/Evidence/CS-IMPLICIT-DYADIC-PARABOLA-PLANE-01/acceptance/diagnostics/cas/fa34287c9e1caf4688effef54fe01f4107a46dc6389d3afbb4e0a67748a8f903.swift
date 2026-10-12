/// Sealed exact bijection between the original host graph and its one-T reduction.
public struct OriginalImplicitCurveGraphReduction: Sendable {
    public typealias Field = OriginalExactScalarDomain
    public typealias Polynomial = ExactPolynomial<Field>
    public typealias Graph = OriginalParametricGraphReceipt<OriginalImplicitCurveSnapshot,Field,OriginalImplicitCurveGraphEvidence>
    public let original: Graph
    public let graph: Graph
    /// Univariate original coordinates in [T, firstU, firstV, secondU, secondV] order.
    public let originalCoordinates: [Polynomial]
    public let proofDepth: ExactScalarDepth

    init(original: Graph, graph: Graph, originalCoordinates: [Polynomial], proofDepth: ExactScalarDepth) {
        self.original = original; self.graph = graph
        self.originalCoordinates = originalCoordinates; self.proofDepth = proofDepth
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try original.source.require(limits); try graph.source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            guard original.source.owner === graph.source.owner,
                original.source.owner === original.evidence.source.owner,
                graph.source.owner === graph.evidence.source.owner else {
                throw OriginalSourceIssuanceFailure.foreignBinding
            }
            guard original.layout.variableCount == 5, original.layout.parameters.count == 1,
                original.layout.parameters[0] == 0, original.layout.auxiliaries.count == 4,
                graph.layout.variableCount == 1, graph.layout.parameters.count == 1,
                graph.layout.parameters[0] == 0, graph.layout.auxiliaries.isEmpty,
                originalCoordinates.count == 5, original.conditions.count == graph.conditions.count else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            for axis in 0..<4 {
                try a.consumeWork(1)
                guard original.layout.auxiliaries[axis] == axis+1 else { throw OriginalSourceIssuanceFailure.invalidChart }
            }
            try original.evidence.admitProof(limits:limits,using:&a)
            func polynomial(_ p: Polynomial) throws {
                try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
                for term in p.terms {
                    try a.consumeWork(1); _ = try graph.field.importing(term.coefficient,using:&a)
                }
            }
            func retainedGraph(_ value: borrowing Graph) throws {
                try a.admitDepth(value:value.proofDepth.value,coefficient:value.proofDepth.coefficient)
                for bound in value.support {
                    _ = try graph.field.importing(bound.lower,using:&a)
                    _ = try graph.field.importing(bound.upper,using:&a)
                }
                for p in value.homogeneous { try polynomial(p) }
                for condition in value.conditions { try polynomial(condition.polynomial) }
                for p in value.parameterTransport.numerators { try polynomial(p) }
                for p in value.parameterTransport.denominators { try polynomial(p) }
            }
            try retainedGraph(original); try retainedGraph(graph)
            for p in originalCoordinates { try polynomial(p) }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
