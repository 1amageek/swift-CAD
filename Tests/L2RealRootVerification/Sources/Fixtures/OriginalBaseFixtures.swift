import L0
import L1
import L2
public enum OriginalBaseFixtures {
    struct Preparation: RationalAlgebraAdmitting {
        var work = 0
        var storage = 0
        mutating func consumeExactWork(_ units: Int) throws {
            guard units >= 0, units <= 50_000_000 - work else { throw ExactScalarFailure.resourceLimit(.work) }
            work += units
        }
        mutating func retainExactStorage(_ words: Int) throws {
            guard words >= 0, words <= 50_000_000 - storage else { throw ExactScalarFailure.resourceLimit(.storage) }
            storage += words
        }
        mutating func visitExactCell(depth: Int) throws {
            guard (0...100).contains(depth) else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard (0...100).contains(depth) else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        }
    }
    public static func run() throws {
        var preparation = Preparation()
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &preparation)
        let law = try ExactBivariatePolynomial.monomial(u: 2, v: 0, coefficient: .one, usage: &preparation)
            .subtracting(.constant(two, usage: &preparation), usage: &preparation)
        let selected = try ExactUnivariateRootIsolator().isolate(law, lower: .one, upper: two, maximumDepth: 100, usage: &preparation)[0]
        let original = try ExactAlgebraicRealRoot(polynomial: law, isolation: selected, usage: &preparation)
            .refined(maximumWidth: .originalDouble(0.0625, usage: &preparation), maximumDepth: 100, usage: &preparation)
        var a = ExactScalarLedger(limits: try .init(work: 100_000_000, storageBytes: 200_000_000, valueDepth: 100, coefficientDepth: 100))
        let f = try OriginalExactScalarDomain(root: original, axis: .coefficient,
            maximumValueDepth: 100, maximumCoefficientDepth: 100, using: &a)
        let alpha = try f.generator(using: &a)
        let d = try ExactRealRootDomain(field: f, using: &a), p = d.polynomials
        let source = try d.bind(p.subtracting(p.variable(0, using: &a), p.constant(alpha, using: &a), using: &a), using: &a)
        let singleton = try d.domain(lower: .finite(alpha), upper: .finite(alpha), using: &a)
        let result = try d.isolate(source, in: singleton, limits: .init(maximumRoots: 1), using: &a)
        try RootFixtures.require(result.roots.count == 1 && result.depth.coefficient >= original.isolation.isolationDepth)
        let base = try ExactAlgebraicScalarDomain.base(field: f, maximumExtensionLevel: 1, using: &a)
        let coefficient = try base.importingBase(alpha, using: &a)
        let rd = try ExactRealRootDomain(field: base, using: &a), rp = rd.polynomials
        let rs = try rd.bind(rp.subtracting(rp.variable(0, using: &a), rp.constant(coefficient, using: &a), using: &a), using: &a)
        let all = try rd.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        let root = try rd.isolate(rs, in: all, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extensionField = try base.adjoin(root, using: &a)
        try RootFixtures.require(extensionField.domain.compare(extensionField.generator,
            extensionField.embedding.importing(coefficient, using: &a), using: &a) == .equal)
        print("PASS: existing algebraic base coefficients and inherited coefficient depth")
    }
}
