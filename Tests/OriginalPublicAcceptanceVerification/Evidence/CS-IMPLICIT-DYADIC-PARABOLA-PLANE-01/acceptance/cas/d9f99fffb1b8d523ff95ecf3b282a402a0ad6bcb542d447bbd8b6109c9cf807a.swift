import CADCore

/// Shared checked evaluation primitives for original rational graph publication.
enum OriginalRationalGraphPointAccess {
    typealias Base = OriginalExactScalarDomain
    typealias Algebraic = ExactAlgebraicScalarDomain<Base>

    static func requireIdentity<Source: Sendable, Evidence: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,Base,Evidence>, arity: Int, using a: inout A) throws {
        try a.admitDepth(value: graph.proofDepth.value, coefficient: graph.proofDepth.coefficient)
        guard graph.layout.variableCount == arity, graph.layout.parameters.count == arity,
            graph.polynomials.variableCount == arity, graph.homogeneous.count == 4,
            graph.parameterTransport.numerators.count == arity,
            graph.parameterTransport.denominators.count == arity else {
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
        for axis in 0..<arity {
            try a.consumeWork(1)
            guard graph.layout.parameters[axis] == axis else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            let ring = graph.polynomials
            let difference = try ring.subtracting(graph.parameterTransport.numerators[axis],
                ring.multiplying(ring.variable(axis, using: &a), graph.parameterTransport.denominators[axis], using: &a), using: &a)
            // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary rational graph point
            // publisher currently accepts proved identity parameter transports.
            // Nonidentity/auxiliary charts need checked local numeric preimages
            // before their authored tuples may be evaluated for publication.
            guard try ring.isZero(difference, using: &a) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        }
    }

    static func derivative<Source: Sendable, Evidence: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,Base,Evidence>, at: [Algebraic.Value], axis: Int,
        field: Algebraic, using a: inout A) throws -> [Algebraic.Value] {
        let ring = try ExactPolynomialDomain(field: field, variableCount: at.count, using: &a)
        let w = try imported(graph.homogeneous[3], into: ring, using: &a)
        let weight = try ring.evaluated(w, at: at, using: &a).value
        guard try field.sign(of: weight, using: &a) != .zero else { throw ExactGeometricRelationFailure.invalidCoverage }
        let dw = try ring.evaluated(ring.differentiated(w, in: axis, using: &a), at: at, using: &a).value
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Algebraic.Value.self))
        var result: [Algebraic.Value] = []; result.reserveCapacity(3)
        for coordinate in 0..<3 {
            let p = try imported(graph.homogeneous[coordinate], into: ring, using: &a)
            let value = try ring.evaluated(p, at: at, using: &a).value
            let dp = try ring.evaluated(ring.differentiated(p, in: axis, using: &a), at: at, using: &a).value
            result.append(try field.subtracting(field.multiplying(dp, weight, using: &a), field.multiplying(value, dw, using: &a), using: &a))
        }
        return result
    }

    static func position<Source: Sendable, Evidence: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,Base,Evidence>, numbers: [Double], offset: Int,
        field: Base, limits: OriginalDomainIdentityLimits, using a: inout A) throws -> [OriginalExactScalar]? {
        let n = graph.layout.variableCount
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: OriginalExactScalar.self))
        var at: [OriginalExactScalar] = []; at.reserveCapacity(n)
        for axis in 0..<n { at.append(try graph.field.binary64(exactly: numbers[offset+axis], using: &a)) }
        guard try graph.admits(at, limits: limits.source, using: &a) else { return nil }
        let weight = try graph.polynomials.evaluated(graph.homogeneous[3], at: at, using: &a).value
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: OriginalExactScalar.self))
        var result: [OriginalExactScalar] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            result.append(try field.importing(graph.field.dividing(graph.polynomials.evaluated(graph.homogeneous[axis], at: at, using: &a).value,
                weight, using: &a), using: &a))
        }
        return result
    }

    static func imported<A: ExactScalarAdmission & ~Copyable>(_ law: ExactPolynomial<Base>,
        into ring: ExactPolynomialDomain<Algebraic>, using a: inout A) throws -> ExactPolynomial<Algebraic> {
        try a.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: law.terms.count, of: ExactPolynomialTerm<Algebraic.Value>.self))
        var terms: [ExactPolynomialTerm<Algebraic.Value>] = []; terms.reserveCapacity(law.terms.count)
        for term in law.terms {
            try a.consumeWork(1)
            terms.append(.init(powers: term.powers, coefficient: try ring.field.importingBase(term.coefficient, using: &a)))
        }
        return try ring.polynomial(terms: terms, using: &a)
    }

}
