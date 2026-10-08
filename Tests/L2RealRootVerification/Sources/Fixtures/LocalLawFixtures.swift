import L0
import L1
import L2

public enum LocalLawFixtures {
    public static func verify() throws {
        typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
        var a = ExactScalarLedger(limits: try .init(work: 16_777_216, storageBytes: 200_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let base = try Field.base(field: .init(), maximumExtensionLevel: 2, using: &a)
        let domain = try ExactRealRootDomain(field: base, using: &a), p = domain.polynomials
        let x = try p.variable(0, using: &a), square = try p.multiplying(x, x, using: &a)
        let q2 = try p.subtracting(square, p.constant(base.integer(2, using: &a), using: &a), using: &a)
        let q3 = try p.subtracting(square, p.constant(base.integer(3, using: &a), using: &a), using: &a)
        let q5 = try p.subtracting(square, p.constant(base.integer(5, using: &a), using: &a), using: &a)
        let law = try p.multiplying(p.multiplying(q2, q3, using: &a), q5, using: &a)
        let selected = try domain.domain(lower: .finite(base.integer(1, using: &a)),
            upper: .finite(base.dividing(base.integer(3, using: &a), base.integer(2, using: &a), using: &a)), using: &a)
        let root = try domain.isolate(domain.bind(law, using: &a), in: selected, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extensionValue = try base.adjoin(root, using: &a), field = extensionValue.domain
        let alpha = extensionValue.generator, one = try field.integer(1, using: &a)
        let alphaSquare = try field.multiplying(alpha, alpha, using: &a)
        let d3 = try field.subtracting(alphaSquare, field.integer(3, using: &a), using: &a)
        let d5 = try field.subtracting(alphaSquare, field.integer(5, using: &a), using: &a)
        let first = try field.dividing(one, d3, using: &a), second = try field.dividing(one, d5, using: &a)
        guard let firstLaw = first.calculation, let secondLaw = second.calculation else {
            throw ExactRealRootFailure.invalidEvidence
        }
        try RootFixtures.require(firstLaw.originalRoot.ordinal == root.ordinal && firstLaw.selectedRoot.multiplicity == root.multiplicity)
        try RootFixtures.require(firstLaw.definingSource.original.terms.first!.powers[0] == 4)
        try RootFixtures.require(secondLaw.definingSource.original.terms.first!.powers[0] == 4)
        let product = try field.multiplying(first, second, using: &a)
        guard let common = product.calculation else { throw ExactRealRootFailure.invalidEvidence }
        try RootFixtures.require(common.definingSource.original.terms.first!.powers[0] == 2)
        try RootFixtures.require(field.compare(product, field.dividing(one, field.integer(3, using: &a), using: &a), using: &a) == .equal)
        let sum = try field.adding(first, second, using: &a)
        try RootFixtures.require(field.compare(sum, field.dividing(field.integer(-4, using: &a), field.integer(3, using: &a), using: &a), using: &a) == .equal)
        try RootFixtures.require(alpha.calculation == nil && root.source.original.terms.first!.powers[0] == 6)
        try RootFixtures.require(firstLaw.definingSource.original.terms.first!.powers[0] == 4)
        let zero = try field.subtracting(alphaSquare, field.integer(2, using: &a), using: &a)
        do {
            _ = try field.dividing(zero, zero, using: &a)
            throw ExactScalarFailure.invalidEvidence
        } catch ExactScalarFailure.divisionByZero { }
        let zeroFraction = try field.dividing(zero, d3, using: &a)
        try RootFixtures.require(field.sign(of: zeroFraction, using: &a) == .zero)
        var independent = ExactScalarLedger(limits: try .init(work: 16_777_216, storageBytes: 200_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let retainedField = try Field(retaining: product, using: &independent)
        try RootFixtures.require(retainedField.sign(of: product, using: &independent) == .positive)
        print("PASS: reducible local inverses, mixed immutable laws, original identity and uncancelled zero denominator")
    }
}
