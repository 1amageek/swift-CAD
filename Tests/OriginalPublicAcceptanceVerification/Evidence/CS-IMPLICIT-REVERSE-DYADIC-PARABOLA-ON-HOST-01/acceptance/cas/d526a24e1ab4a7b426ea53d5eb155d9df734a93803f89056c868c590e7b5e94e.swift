/// Sealed complete closed global-T cover of the actual retained implicit cells.
public struct OriginalFiniteImplicitCurveGraphCoverage: Sendable {
    public typealias Field = OriginalExactScalarDomain
    public let source: OriginalSourceBinding<OriginalImplicitCurveSnapshot>
    public let field: Field
    public let reductions: [OriginalImplicitCurveGraphReduction]
    public let support: OriginalSourceParameterInterval<Field.Value>
    public let proofDepth: ExactScalarDepth

    init(source: OriginalSourceBinding<OriginalImplicitCurveSnapshot>, field: Field,
        reductions: [OriginalImplicitCurveGraphReduction], support: OriginalSourceParameterInterval<Field.Value>,
        proofDepth: ExactScalarDepth) {
        self.source = source; self.field = field; self.reductions = reductions
        self.support = support; self.proofDepth = proofDepth
    }

    /// Validates the original order, closed cover, local maps and every shared host tuple.
    static func validateCover<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<OriginalImplicitCurveSnapshot>, field: Field,
        reductions: borrowing [OriginalImplicitCurveGraphReduction],
        support: OriginalSourceParameterInterval<Field.Value>, using a: inout A) throws {
        try a.checkpoint()
        let count = source.original.original.cells.count
        guard (count == 1 || count == 2), reductions.count == count else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        let zero = try field.integer(0,using:&a), one = try field.integer(1,using:&a)
        let countValue = try field.integer(count,using:&a)
        guard try field.compare(support.lower,zero,using:&a) == .equal,
            try field.compare(support.upper,one,using:&a) == .equal else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Field.Value.self))
        var coordinate = [zero]
        for index in reductions.indices {
            try a.consumeWork(1)
            let reduction = reductions[index], evidence = reduction.original.evidence
            guard reduction.original.source.owner === source.owner,
                reduction.graph.source.owner === source.owner, evidence.source.owner === source.owner,
                reduction.graph.evidence.source.owner === source.owner else {
                throw OriginalSourceIssuanceFailure.foreignBinding
            }
            guard reduction.cellOrdinal == index, reduction.graph.evidence.cellOrdinal == index,
                reduction.originalCoordinates.count == 5,
                source.original.original.cells[index].freeParameter == .firstV,
                source.original.original.cells[index].direction == .forward
                    || (count == 1 && source.original.original.cells[index].direction == .reversed) else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            _ = try field.importing(evidence.field.integer(0,using:&a),using:&a)
            _ = try field.importing(reduction.graph.field.integer(0,using:&a),using:&a)
            let ordinal = try field.integer(index,using:&a)
            let lower = try field.dividing(ordinal,countValue,using:&a)
            let upper = try field.dividing(field.integer(index+1,using:&a),countValue,using:&a)
            guard try field.compare(reduction.globalSupport.lower,lower,using:&a) == .equal,
                try field.compare(reduction.globalSupport.upper,upper,using:&a) == .equal,
                try field.compare(reduction.graph.evidence.globalSupport.lower,lower,using:&a) == .equal,
                try field.compare(reduction.graph.evidence.globalSupport.upper,upper,using:&a) == .equal else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            let ring = evidence.parameterPolynomials
            let parameter = try ring.variable(0,using:&a)
            let unit = try ring.constant(one,using:&a)
            func span(_ graph: borrowing OriginalImplicitCurveGraphReduction.Graph) throws {
                guard graph.support.count == 1, graph.includesUpperBoundary.count == 1,
                    graph.includesUpperBoundary[0],
                    graph.parameterTransport.numerators.count == 1,
                    graph.parameterTransport.denominators.count == 1,
                    try ring.equals(graph.parameterTransport.numerators[0],parameter,using:&a),
                    try ring.equals(graph.parameterTransport.denominators[0],unit,using:&a),
                    try field.compare(graph.support[0].lower,lower,using:&a) == .equal,
                    try field.compare(graph.support[0].upper,upper,using:&a) == .equal else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
            }
            try span(reduction.original); try span(reduction.graph)
            let local = try ring.subtracting(ring.scaled(parameter,by:countValue,using:&a),
                ring.constant(ordinal,using:&a),using:&a)
            guard try ring.equals(local,reduction.localParameter,using:&a),
                try ring.equals(local,reduction.graph.evidence.localParameter,using:&a),
                try ring.equals(parameter,reduction.originalCoordinates[0],using:&a) else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            coordinate[0] = lower
            guard try field.compare(ring.evaluated(local,at:coordinate,using:&a).value,zero,using:&a) == .equal else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            if index > 0 {
                let previous = reductions[index-1], previousRing = previous.original.evidence.parameterPolynomials
                guard try field.compare(previous.globalSupport.upper,lower,using:&a) == .equal else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                for axis in 1..<5 {
                    try a.consumeWork(1)
                    let left = try previousRing.evaluated(previous.originalCoordinates[axis],at:coordinate,using:&a).value
                    let right = try ring.evaluated(reduction.originalCoordinates[axis],at:coordinate,using:&a).value
                    guard try field.compare(left,right,using:&a) == .equal else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                }
            }
            coordinate[0] = upper
            guard try field.compare(ring.evaluated(local,at:coordinate,using:&a).value,one,using:&a) == .equal else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
        }
        try a.checkpoint()
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            try Self.validateCover(source:source,field:field,reductions:reductions,support:support,using:&a)
            for reduction in reductions {
                try a.consumeWork(1); try reduction.admitProof(limits:limits,using:&a)
            }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
