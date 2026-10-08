import L0
import L1
import L2

public enum FieldFixtures {
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    static func root(_ field: Field, degree: Int, right: Field.Value, _ a: inout ExactScalarLedger) throws -> ExactRealRoot<Field> {
        let d = try ExactRealRootDomain(field: field, using: &a)
        let p = d.polynomials, one = try field.integer(1, using: &a)
        let law = try p.polynomial(terms: [.init(powers: [degree], coefficient: one),
            .init(powers: [0], coefficient: field.negated(right, using: &a))], using: &a)
        let source = try d.bind(law, refinementAxis: .coefficient, using: &a)
        let domain = try d.domain(lower: .finite(one), upper: .finite(field.integer(2, using: &a)), using: &a)
        let roots = try d.isolate(source, in: domain, limits: .init(maximumRoots: 1), using: &a).roots
        try RootFixtures.require(roots.count == 1); return roots[0]
    }
    public static func tower() throws {
        var a = ExactScalarLedger(limits: try .init(work: 16_777_216, storageBytes: 200_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let base = try Field.base(field: .init(), maximumExtensionLevel: 4, using: &a)
        let two = try base.integer(2, using: &a)
        let first = try base.adjoin(root(base, degree: 2, right: two, &a), using: &a)
        let f = first.domain, alpha = first.generator
        try RootFixtures.require(f.compare(f.multiplying(alpha, alpha, using: &a), f.integer(2, using: &a), using: &a) == .equal)
        let second = try f.adjoin(root(f, degree: 2, right: alpha, &a), using: &a)
        let g = second.domain, beta = second.generator
        let retainedAlpha = try second.embedding.importing(alpha, using: &a)
        try RootFixtures.require(g.compare(g.multiplying(beta, beta, using: &a), retainedAlpha, using: &a) == .equal)
        try RootFixtures.require(g.sign(of: g.subtracting(beta, g.integer(1, using: &a), using: &a), using: &a) == .positive)
        let inverse = try g.dividing(g.integer(1, using: &a), beta, using: &a)
        try RootFixtures.require(g.compare(g.multiplying(inverse, beta, using: &a), g.integer(1, using: &a), using: &a) == .equal)
        // A runtime third extension keeps the same generic scalar/domain type.
        let third = try g.adjoin(root(g, degree: 1, right: beta, &a), using: &a)
        try RootFixtures.require(third.domain.compare(third.generator, third.embedding.importing(beta, using: &a), using: &a) == .equal)
        try RootFixtures.require(third.domain.extensionLevel == 3)
        print("PASS: runtime algebraic tower and retained ancestor embeddings")
    }
    public static func denominatorUnits() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let base = try Field.base(field: ExactRationalScalarDomain(), maximumExtensionLevel: 2, using: &a)
        let domain = try ExactRealRootDomain(field: base, using: &a)
        let p = domain.polynomials, x = try p.variable(0, using: &a)
        let law = try p.adding(p.subtracting(p.multiplying(x, x, using: &a),
            p.scaled(x, by: base.integer(15, using: &a), using: &a), using: &a),
            p.constant(base.integer(8, using: &a), using: &a), using: &a)
        let selected = try domain.domain(lower: .finite(base.integer(0, using: &a)),
            upper: .finite(base.integer(1, using: &a)), using: &a)
        let root = try domain.isolate(domain.bind(law, using: &a), in: selected,
            limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extensionValue = try base.adjoin(root, using: &a), field = extensionValue.domain
        let u = extensionValue.generator, one = try field.integer(1, using: &a)
        let denominator = try field.subtracting(field.integer(2, using: &a), u, using: &a)
        let inverse = try field.dividing(one, denominator, using: &a)
        var product = one, reciprocal = one
        for _ in 0..<12 {
            product = try field.multiplying(product, denominator, using: &a)
            reciprocal = try field.multiplying(reciprocal, inverse, using: &a)
        }
        try RootFixtures.require(field.compare(field.multiplying(product, reciprocal, using: &a), one, using: &a) == .equal)
        try RootFixtures.require(field.sign(of: product, using: &a) == .positive)
        let vanished = try field.adding(field.subtracting(field.multiplying(u, u, using: &a),
            field.multiplying(field.integer(15, using: &a), u, using: &a), using: &a),
            field.integer(8, using: &a), using: &a)
        do {
            _ = try field.dividing(one, vanished, using: &a)
            throw ExactScalarFailure.invalidEvidence
        } catch ExactScalarFailure.divisionByZero { }
        print("PASS: denominator units preserve exact inverses and zero rejection within depth32")
    }

    public static func reducible() throws {
        var a = ExactScalarLedger(limits: try .init(work: 100_000_000, storageBytes: 150_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let base = try Field.base(field: .init(), maximumExtensionLevel: 1, using: &a)
        let d = try ExactRealRootDomain(field: base, using: &a), p = d.polynomials
        let x = try p.variable(0, using: &a), xx = try p.multiplying(x, x, using: &a)
        let two = try p.constant(base.integer(2, using: &a), using: &a)
        let three = try p.constant(base.integer(3, using: &a), using: &a)
        let source = try d.bind(p.multiplying(p.subtracting(xx, two, using: &a), p.subtracting(xx, three, using: &a), using: &a), using: &a)
        let one = try base.integer(1, using: &a)
        let half = try base.dividing(base.integer(3, using: &a), base.integer(2, using: &a), using: &a)
        let selected = try d.domain(lower: .finite(one), upper: .finite(half), using: &a)
        let root = try d.isolate(source, in: selected, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let e = try base.adjoin(root, using: &a), f = e.domain, alpha = e.generator
        let square = try f.multiplying(alpha, alpha, using: &a)
        let zero = try f.subtracting(square, f.integer(2, using: &a), using: &a)
        try RootFixtures.require(f.sign(of: zero, using: &a) == .zero)
        do { _ = try f.dividing(f.integer(1, using: &a), zero, using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactScalarFailure.divisionByZero {}
        let denominator = try f.subtracting(square, f.integer(3, using: &a), using: &a)
        let inverse = try f.dividing(f.integer(1, using: &a), denominator, using: &a)
        try RootFixtures.require(f.sign(of: inverse, using: &a) == .negative)
        print("PASS: reducible root law and selected-root denominator decisions")
    }
    public static func failures() throws {
        var a = ExactScalarLedger(limits: try .init(work: 100_000_000, storageBytes: 150_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let base = try Field.base(field: .init(), maximumExtensionLevel: 1, using: &a)
        let root = try root(base, degree: 2, right: base.integer(2, using: &a), &a)
        let first = try base.adjoin(root, using: &a), sibling = try base.adjoin(root, using: &a)
        do { _ = try first.domain.importing(sibling.generator, using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactScalarFailure.incompatibleDomain {}
        let next = try self.root(first.domain, degree: 1, right: first.generator, &a)
        do { _ = try first.domain.adjoin(next, using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.extensionLevelLimit {}
        let unrelated = try Field.base(field: .init(), maximumExtensionLevel: 1, using: &a)
        do { _ = try unrelated.adjoin(root, using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.incompatibleDomain {}
        var storage = ExactScalarLedger(limits: try .init(work: 100_000, storageBytes: 0, valueDepth: 100, coefficientDepth: 100))
        do { _ = try first.domain.sign(of: first.generator, using: &storage); throw ExactRealRootFailure.invalidEvidence }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        var cancelled = ExactScalarLedger(limits: try .init(work: 100_000, storageBytes: 100_000, valueDepth: 100, coefficientDepth: 100))
        cancelled.cancel()
        do { _ = try first.domain.importing(first.generator, using: &cancelled); throw ExactRealRootFailure.invalidEvidence }
        catch ExactScalarFailure.cancelled {}
        print("PASS: incompatible owners, extension ceiling and scalar failures")
    }
}
