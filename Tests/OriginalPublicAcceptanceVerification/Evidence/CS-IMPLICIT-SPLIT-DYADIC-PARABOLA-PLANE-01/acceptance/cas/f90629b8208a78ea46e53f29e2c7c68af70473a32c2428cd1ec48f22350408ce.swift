/// Sealed exact bijection between the original host graph and its one-T reduction.
public struct OriginalImplicitCurveGraphReduction: Sendable {
    public typealias Field = OriginalExactScalarDomain
    public typealias Polynomial = ExactPolynomial<Field>
    public typealias Graph = OriginalParametricGraphReceipt<OriginalImplicitCurveSnapshot,Field,OriginalImplicitCurveGraphEvidence>
    public let original: Graph
    public let graph: Graph
    public var cellOrdinal: Int { original.evidence.cellOrdinal }
    public var globalSupport: OriginalSourceParameterInterval<Field.Value> { original.evidence.globalSupport }
    public var localParameter: Polynomial { original.evidence.localParameter }
    public let substitutedConditions: [OriginalParametricGraphCondition<Field>]
    public let conditionRanges: [OriginalSourceParameterInterval<Field.Value>]
    public let retainedConditionOrdinals: [Int]
    public let eliminatedConditionOrdinals: [Int]
    /// Univariate original coordinates in [T, firstU, firstV, secondU, secondV] order.
    public let originalCoordinates: [Polynomial]
    public let proofDepth: ExactScalarDepth

    init(original: Graph, graph: Graph, substitutedConditions: [OriginalParametricGraphCondition<Field>],
        conditionRanges: [OriginalSourceParameterInterval<Field.Value>], retainedConditionOrdinals: [Int],
        eliminatedConditionOrdinals: [Int], originalCoordinates: [Polynomial], proofDepth: ExactScalarDepth) {
        self.original = original; self.graph = graph
        self.substitutedConditions = substitutedConditions; self.conditionRanges = conditionRanges
        self.retainedConditionOrdinals = retainedConditionOrdinals; self.eliminatedConditionOrdinals = eliminatedConditionOrdinals
        self.originalCoordinates = originalCoordinates; self.proofDepth = proofDepth
    }

    /// A conservative range is sufficient only when the entire range satisfies the relation.
    static func rangeProves<A: ExactScalarAdmission & ~Copyable>(
        _ relation: OriginalParametricGraphCondition<Field>.Relation,
        range: OriginalSourceParameterInterval<Field.Value>, field: Field, zero: Field.Value,
        using a: inout A) throws -> Bool {
        guard try field.compare(range.lower,range.upper,using:&a) != .greater else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        let lower = try field.compare(range.lower,zero,using:&a)
        let upper = try field.compare(range.upper,zero,using:&a)
        switch relation {
        case .equal: return lower == .equal && upper == .equal
        case .notEqual: return lower == .greater || upper == .less
        case .positive: return lower == .greater
        case .nonnegative: return lower != .less
        }
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try original.source.require(limits); try graph.source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            guard original.source.owner === graph.source.owner,
                original.source.owner === original.evidence.source.owner,
                graph.source.owner === graph.evidence.source.owner,
                cellOrdinal == graph.evidence.cellOrdinal else {
                throw OriginalSourceIssuanceFailure.foreignBinding
            }
            guard original.layout.variableCount == 5, original.layout.parameters.count == 1,
                original.layout.parameters[0] == 0, original.layout.auxiliaries.count == 4,
                graph.layout.variableCount == 1, graph.layout.parameters.count == 1,
                graph.layout.parameters[0] == 0, graph.layout.auxiliaries.isEmpty,
                originalCoordinates.count == 5, original.conditions.count == substitutedConditions.count,
                conditionRanges.count == substitutedConditions.count,
                retainedConditionOrdinals.count == graph.conditions.count else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            let partitionCount = retainedConditionOrdinals.count.addingReportingOverflow(eliminatedConditionOrdinals.count)
            guard !partitionCount.overflow,partitionCount.partialValue == substitutedConditions.count else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:substitutedConditions.count,of:Bool.self))
            var seen = [Bool](repeating:false,count:substitutedConditions.count)
            let zero = try graph.field.integer(0,using:&a)
            for ordinal in retainedConditionOrdinals.indices {
                try a.consumeWork(1)
                let index = retainedConditionOrdinals[ordinal]
                guard index >= 0,index < seen.count,!seen[index],
                    graph.conditions[ordinal].relation == substitutedConditions[index].relation,
                    try graph.polynomials.equals(graph.conditions[ordinal].polynomial,
                        substitutedConditions[index].polynomial,using:&a) else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                seen[index] = true
                _ = try Self.rangeProves(substitutedConditions[index].relation,
                    range:conditionRanges[index],field:graph.field,zero:zero,using:&a)
            }
            for index in eliminatedConditionOrdinals {
                try a.consumeWork(1)
                guard index >= 0,index < seen.count,!seen[index],
                    try Self.rangeProves(substitutedConditions[index].relation,
                        range:conditionRanges[index],field:graph.field,zero:zero,using:&a) else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                seen[index] = true
            }
            for present in seen {
                try a.consumeWork(1)
                guard present else { throw OriginalSourceIssuanceFailure.invalidChart }
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
            for index in substitutedConditions.indices {
                try polynomial(substitutedConditions[index].polynomial)
                _ = try graph.field.importing(conditionRanges[index].lower,using:&a)
                _ = try graph.field.importing(conditionRanges[index].upper,using:&a)
            }
            for p in originalCoordinates { try polynomial(p) }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
