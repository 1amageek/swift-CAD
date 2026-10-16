import CADCore

/// Checked beta-field circle/root law; mixed coordinates retain independent alpha.
public struct OriginalConeConeSurfaceSectionValues: Sendable {
    public typealias Field = OriginalFullConeConeSurfaceSnapshot.Field
    public let halfAngle: Field.Value
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let parameterizedSine: Field.Value
    public let parameterizedCosine: Field.Value
    public let radialRoot: Field.Value
    public let proofDepth: ExactScalarDepth
    private init(halfAngle: Field.Value, field: Field, sine: Field.Value, cosine: Field.Value,
        parameterizedSine: Field.Value, parameterizedCosine: Field.Value, radialRoot: Field.Value, proofDepth: ExactScalarDepth) {
        self.halfAngle = halfAngle; self.field = field; self.sine = sine; self.cosine = cosine
        self.parameterizedSine = parameterizedSine; self.parameterizedCosine = parameterizedCosine
        self.radialRoot = radialRoot; self.proofDepth = proofDepth
    }
    static func issue<A: ExactScalarAdmission & ~Copyable>(source: OriginalFullConeConeSurfaceSnapshot,
        chart: Int, halfAngle t: Field.Value, using a: inout A) throws -> Self {
        try a.withProofScope { a in
            guard chart == 0 || chart == 1 else { throw OriginalSourceIssuanceFailure.invalidChart }
            let base = try Field(retaining: t, using: &a)
            let sb = try base.importing(source.parameterizedSine, using: &a)
            let cb = try base.importing(source.parameterizedCosine, using: &a)
            let one = try base.integer(1, using: &a), square = try base.multiplying(t, t, using: &a)
            let q = try base.adding(one, square, using: &a)
            var sine = try base.dividing(base.multiplying(base.integer(2, using: &a), t, using: &a), q, using: &a)
            var cosine = try base.dividing(base.subtracting(one, square, using: &a), q, using: &a)
            if chart == 1 { sine = try base.negated(sine, using: &a); cosine = try base.negated(cosine, using: &a) }
            let f: Field, root: Field.Value
            if try base.sign(of: cosine, using: &a) == .zero { f = base; root = one }
            else if try base.compare(t, base.integer(0, using: &a), using: &a) == .equal { f = base; root = cb }
            else {
                let product = try base.multiplying(sb, cosine, using: &a)
                let radicand = try base.subtracting(one, base.multiplying(product, product, using: &a), using: &a)
                let roots = try ExactRealRootDomain(field: base, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactPolynomialTerm<Field.Value>.self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Int.self))
                let polynomial = try roots.polynomials.polynomial(terms: [
                    .init(powers: [2], coefficient: one), .init(powers: [0], coefficient: try base.negated(radicand, using: &a))], using: &a)
                let bound = try roots.domain(lower: .finite(base.dividing(base.integer(9, using: &a), base.integer(10, using: &a), using: &a)),
                    upper: .finite(base.dividing(base.integer(11, using: &a), base.integer(10, using: &a), using: &a)),
                    includesLower: false, includesUpper: false, using: &a)
                let selected = try roots.isolate(roots.bind(polynomial, using: &a), in: bound, limits: .init(maximumRoots: 1), using: &a)
                guard selected.roots.count == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
                let extended = try base.adjoin(selected.roots[0], using: &a); f = extended.domain; root = extended.generator
            }
            let h = try f.importing(t, using: &a), ss = try f.importing(sine, using: &a), cc = try f.importing(cosine, using: &a)
            let s = try f.importing(sb, using: &a), c = try f.importing(cb, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(halfAngle: h, field: f, sine: ss, cosine: cc,
                parameterizedSine: s, parameterizedCosine: c, radialRoot: root, proofDepth: try a.depth)
            try a.checkpoint(); return result
        }
    }
}
