import CADCore

/// Compiles original forward UV into the retained lifted ring and refines only material.
public struct DefaultOriginalIssuedGraphBoundaryClipper<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable>: OriginalIssuedGraphBoundaryClipping {
    public typealias First = S
    public typealias FirstEvidence = E
    public typealias FirstCover = C
    public typealias Second = T
    public typealias SecondEvidence = F
    public typealias SecondCover = D
    public init() {}

    public func clip<A: ExactScalarAdmission & ~Copyable>(
        _ boundary: OriginalIssuedGraphBoundaryDomain<S, E, C, T, F, D>,
        selection: OriginalNativeBoundaryDomain.Selection, domainLimits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits, using a: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphClippedParameters<S, E, C, T, F, D> {
        do {
            try a.checkpoint()
            let raw = boundary.source.raw
            try raw.admitProof(limits: domainLimits, using: &a)
            typealias Refinement = OriginalIssuedGraphBoundaryRefinement<S, E, C, T, F, D>
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: raw.pairs.count, of: Refinement.self))
            var refinements: [Refinement] = []
            refinements.reserveCapacity(raw.pairs.count)
            for ordinal in raw.pairs.indices {
                try a.consumeWork(1)
                let pair = raw.pairs[ordinal], lifted = pair.relation.projection.original
                var compiler = try OriginalExactBoundaryCompiler<OriginalExactScalarDomain>(selection: lifted, using: &a)
                let uv: (numerators: [ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>],
                         denominator: ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>)
                switch boundary.source.side {
                case .first:
                    guard raw.first.graphs.indices.contains(pair.firstGraphIndex) else { throw NativeExactRelationFailure.invalidDomain }
                    uv = try coordinates(raw.first.graphs[pair.firstGraphIndex], placement: pair.relation.original.firstCoordinates,
                        compiler: compiler, using: &a)
                case .second:
                    guard raw.second.graphs.indices.contains(pair.secondGraphIndex) else { throw NativeExactRelationFailure.invalidDomain }
                    uv = try coordinates(raw.second.graphs[pair.secondGraphIndex], placement: pair.relation.original.secondCoordinates,
                        compiler: compiler, using: &a)
                }
                let root = try compiler.boundary(preparedLoops: boundary.preparedLoops, numerators: uv.numerators,
                    denominator: uv.denominator, selection: selection, &a)
                let instructions = try compiler.instructions(root, &a)
                let source = try compiler.cells.bind(polynomials: compiler.laws, domains: lifted.predicate.source.domains, using: &a)
                let predicate = try compiler.cells.predicate(instructions: instructions, for: source, using: &a)
                let refined = try DefaultOriginalIssuedGraphParameterRefiner<S, E, C, T, F, D>().refine(
                    in: raw, pairOrdinal: ordinal, matching: predicate, limits: domainLimits,
                    cellLimits: cellLimits, topologyLimits: topologyLimits, using: &a)
                let spans = try compiler.boundaryReferences(in: refined.pullback, using: &a)
                refinements.append(.init(parameters: refined, boundarySpans: spans, factorizations: compiler.factorizations))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedGraphClippedParameters<S, E, C, T, F, D>.self))
            let result = OriginalIssuedGraphClippedParameters(boundary: boundary, selection: selection, refinements: refinements)
            try a.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }

    private func coordinates<Source: Sendable, Evidence: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ preparation: OriginalIssuedGraphPreparation<Source, Evidence>, placement: [Int],
        compiler: OriginalExactBoundaryCompiler<OriginalExactScalarDomain>, using a: inout A
    ) throws -> (numerators: [ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>],
                 denominator: ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>) {
        let original = preparation.original.graph, transport = original.parameterTransport
        guard preparation.graph.parameterCount == 2, transport.numerators.count == 2, transport.denominators.count == 2,
            placement.count == preparation.graph.variableCount else { throw NativeExactRelationFailure.invalidDomain }
        let ring = compiler.cells.polynomials, field = compiler.field
        func imported(_ polynomial: ExactPolynomial<OriginalExactScalarDomain>) throws -> ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>> {
            guard polynomial.variableCount == 2 else { throw NativeExactRelationFailure.invalidDomain }
            try a.admitDepth(value: polynomial.depth.value, coefficient: polynomial.depth.coefficient)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: polynomial.termCount,
                of: ExactPolynomialTerm<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>.Value>.self))
            var terms: [ExactPolynomialTerm<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>.Value>] = []
            terms.reserveCapacity(polynomial.termCount)
            for term in polynomial.terms {
                try a.consumeWork(1)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: ring.variableCount, of: Int.self))
                var powers = Array(repeating: 0, count: ring.variableCount)
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    guard placement[axis] >= 0, placement[axis] < powers.count else { throw NativeExactRelationFailure.invalidDomain }
                    powers[placement[axis]] = term.powers[axis]
                }
                terms.append(.init(powers: powers, coefficient: try field.importingBase(term.coefficient, using: &a)))
            }
            return try ring.polynomial(terms: terms, using: &a)
        }
        let u = try imported(transport.numerators[0]), v = try imported(transport.numerators[1])
        let du = try imported(transport.denominators[0]), dv = try imported(transport.denominators[1])
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>.self))
        return (try [ring.multiplying(u, dv, using: &a), ring.multiplying(v, du, using: &a)],
                try ring.multiplying(du, dv, using: &a))
    }
}
