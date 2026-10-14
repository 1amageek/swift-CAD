import CADCore

/// Source-issued exact unit-circle position law and its two selected slants.
public struct OriginalSphereConeSurfaceSectionValues: Sendable {
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public let halfAngle: Field.Value
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let plusSlant: Field.Value
    public let minusSlant: Field.Value
    public let isDoubleRoot: Bool
    public let proofDepth: ExactScalarDepth
    private let sourceSine: Field.Value
    private let sourceCosine: Field.Value
    private let apexX: Int
    static func issue<A: ExactScalarAdmission & ~Copyable>(halfAngle t: Field.Value, chart: Int,
        sourceSine: Field.Value, sourceCosine: Field.Value, apexX: Int, constant: Int,
        isDoubleRoot: Bool, using a: inout A) throws -> Self {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            let base = try Field(retaining: t, using: &a)
            let s = try base.importing(sourceSine, using: &a), c = try base.importing(sourceCosine, using: &a)
            let one = try base.integer(1, using: &a), two = try base.integer(2, using: &a)
            let square = try base.multiplying(t, t, using: &a), q = try base.adding(one, square, using: &a)
            var sine = try base.dividing(base.multiplying(two, t, using: &a), q, using: &a)
            var cosine = try base.dividing(base.subtracting(one, square, using: &a), q, using: &a)
            if chart == 1 { sine = try base.negated(sine, using: &a); cosine = try base.negated(cosine, using: &a) }
            let b = try base.adding(base.multiplying(base.multiplying(base.integer(apexX, using: &a), s, using: &a), sine, using: &a),
                base.multiplying(base.integer(4, using: &a), c, using: &a), using: &a)
            let field: Field, plus: Field.Value, minus: Field.Value
            if isDoubleRoot { field = base; plus = b; minus = b }
            else {
                let roots = try ExactRealRootDomain(field: base, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: ExactPolynomialTerm<Field.Value>.self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Int.self))
                let polynomial = try roots.polynomials.polynomial(terms: [
                    .init(powers: [2], coefficient: one),
                    .init(powers: [1], coefficient: try base.multiplying(base.integer(-2, using: &a), b, using: &a)),
                    .init(powers: [0], coefficient: try base.integer(constant, using: &a))], using: &a)
                let scope = try roots.domain(lower: .finite(base.integer(4, using: &a)), upper: .finite(base.integer(7, using: &a)),
                    includesLower: false, includesUpper: false, using: &a)
                let isolated = try roots.isolate(roots.bind(polynomial, using: &a), in: scope, limits: .init(maximumRoots: 1), using: &a)
                guard isolated.roots.count == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
                let extended = try base.adjoin(isolated.roots[0], using: &a)
                field = extended.domain; plus = extended.generator
                minus = try field.subtracting(field.importing(base.multiplying(two, b, using: &a), using: &a), plus, using: &a)
            }
            let h = try field.importing(t, using: &a), ss = try field.importing(sine, using: &a), cc = try field.importing(cosine, using: &a)
            let sourceSine = try field.importing(s, using: &a), sourceCosine = try field.importing(c, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let value = Self(halfAngle: h, field: field, sine: ss, cosine: cc, plusSlant: plus, minusSlant: minus,
                isDoubleRoot: isDoubleRoot, proofDepth: try a.depth, sourceSine: sourceSine, sourceCosine: sourceCosine, apexX: apexX)
            try a.checkpoint(); return value
        }
    }
    public func position<A: ExactScalarAdmission & ~Copyable>(branch: Int, using a: inout A)
        throws -> (slant: Field.Value, x: Field.Value, y: Field.Value, z: Field.Value) {
        try a.checkpoint(); try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        guard branch == 0 || branch == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
        let f = field, slant = branch == 0 ? plusSlant : minusSlant
        let radial = try f.multiplying(sourceSine, slant, using: &a)
        let x = try f.subtracting(f.integer(apexX, using: &a), f.multiplying(radial, sine, using: &a), using: &a)
        let y = try f.multiplying(radial, cosine, using: &a)
        let z = try f.adding(f.integer(-4, using: &a), f.multiplying(sourceCosine, slant, using: &a), using: &a)
        try a.checkpoint(); return (slant, x, y, z)
    }
}
