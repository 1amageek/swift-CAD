import CADCore

/// One admitted point section shares its selected root between both source arcs.
public struct OriginalBoundedSphereConeSurfaceSection: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    public let relation: OriginalBoundedSphereConeSurfaceRelation
    public let sourceHalfAngle: Field.Value
    public let halfAngle: Field.Value
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let plusSlant: Field.Value
    public let minusSlant: Field.Value
    public let isSharedEndpoint: Bool
    public let proofDepth: ExactScalarDepth
    private init(relation: OriginalBoundedSphereConeSurfaceRelation, sourceHalfAngle: Field.Value, halfAngle: Field.Value,
        field: Field, sine: Field.Value, cosine: Field.Value, plusSlant: Field.Value,
        minusSlant: Field.Value, isSharedEndpoint: Bool, proofDepth: ExactScalarDepth) {
        self.relation = relation; self.sourceHalfAngle = sourceHalfAngle; self.halfAngle = halfAngle; self.field = field; self.sine = sine
        self.cosine = cosine; self.plusSlant = plusSlant; self.minusSlant = minusSlant
        self.isSharedEndpoint = isSharedEndpoint; self.proofDepth = proofDepth
    }
    static func issue<A: ExactScalarAdmission & ~Copyable>(relation: OriginalBoundedSphereConeSurfaceRelation,
        halfAngle t: Field.Value, using a: inout A) throws -> Self {
        return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            let source = relation.source.original
            let base = try Field(retaining: t, using: &a)
            let sourceSine = try base.importing(source.sine, using: &a)
            let sourceCosine = try base.importing(source.cosine, using: &a)
            let one = try base.integer(1, using: &a), two = try base.integer(2, using: &a)
            let square = try base.multiplying(t, t, using: &a), q = try base.adding(one, square, using: &a)
            let sine = try base.dividing(base.multiplying(two, t, using: &a), q, using: &a)
            let cosine = try base.dividing(base.subtracting(one, square, using: &a), q, using: &a)
            let b = try base.adding(base.multiplying(base.multiplying(two, sourceSine, using: &a), sine, using: &a),
                base.multiplying(base.integer(4, using: &a), sourceCosine, using: &a), using: &a)
            let boundary = try source.criticalField.compare(t, source.lowerHalfAngle, using: &a) == .equal
                || source.criticalField.compare(t, source.upperHalfAngle, using: &a) == .equal
            let f: Field, plus: Field.Value, minus: Field.Value
            if boundary { f = base; plus = b; minus = b }
            else {
                let roots = try ExactRealRootDomain(field: base, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: ExactPolynomialTerm<Field.Value>.self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Int.self))
                let polynomial = try roots.polynomials.polynomial(terms: [
                    .init(powers: [2], coefficient: one),
                    .init(powers: [1], coefficient: try base.multiplying(base.integer(-2, using: &a), b, using: &a)),
                    .init(powers: [0], coefficient: try base.integer(16, using: &a))], using: &a)
                // The retained source bounds give 4<b<9/2 on the interior.
                // P(4)<0 and P(7)>2 isolate only the plus root; the minus is<4.
                let scope = try roots.domain(lower: .finite(base.integer(4, using: &a)), upper: .finite(base.integer(7, using: &a)),
                    includesLower: false, includesUpper: false, using: &a)
                let isolated = try roots.isolate(roots.bind(polynomial, using: &a), in: scope, limits: .init(maximumRoots: 1), using: &a)
                guard isolated.roots.count == 1 else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                let extended = try base.adjoin(isolated.roots[0], using: &a)
                f = extended.domain; plus = extended.generator
                minus = try f.subtracting(f.importing(base.multiplying(two, b, using: &a), using: &a), plus, using: &a)
        }
        let ss = try f.importing(sine, using: &a), cc = try f.importing(cosine, using: &a), depth = try a.depth
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let section = Self(relation: relation, sourceHalfAngle: t, halfAngle: try f.importing(t, using: &a), field: f, sine: ss, cosine: cc,
            plusSlant: plus, minusSlant: minus, isSharedEndpoint: boundary, proofDepth: depth)
        try a.checkpoint(); return section
        }
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(branch: Int, coneCycle: OriginalParameterCycle,
        sphereCycle: OriginalParameterCycle, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalBoundedSphereConeSurfaceMember {
        return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try relation.admitProof(limits: limits, using: &a)
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            guard branch == 0 || branch == 1 else { throw OriginalDomainIdentityFailure.outsideSupport }
            let source = relation.source.original, f = field, slant = branch == 0 ? plusSlant : minusSlant
            let s = try f.importing(source.sine, using: &a), c = try f.importing(source.cosine, using: &a)
            let radial = try f.multiplying(s, slant, using: &a)
            let x = try f.subtracting(f.integer(2, using: &a), f.multiplying(radial, sine, using: &a), using: &a)
            let y = try f.multiplying(radial, cosine, using: &a)
            let z = try f.adding(f.integer(-4, using: &a), f.multiplying(c, slant, using: &a), using: &a)
            let coneOffset = try f.multiplying(f.importing(source.labelPeriod, using: &a), coneCycle.scalar(in: f, using: &a), using: &a)
            let sphereOffset = try f.multiplying(f.importing(source.labelPeriod, using: &a), sphereCycle.scalar(in: f, using: &a), using: &a)
            let depth = try a.depth
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalBoundedSphereConeSurfaceMember.self))
            let result = OriginalBoundedSphereConeSurfaceMember(section: self, branch: branch, slant: slant,
                x: x, y: y, z: z, coneLabelOffset: coneOffset, sphereLabelOffset: sphereOffset, proofDepth: depth)
            try a.checkpoint(); return result
        }
    }
}
