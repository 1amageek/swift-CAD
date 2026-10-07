import L0
import L1
import L2
public enum EdgeFixtures {
    static func ledger() throws -> ExactScalarLedger {
        .init(limits: try .init(work: 80_000_000, storageBytes: 150_000_000, valueDepth: 100, coefficientDepth: 100))
    }
    public static func finalCancellationAndStorage() throws {
        var a = try ledger()
        let f = ExactRationalScalarDomain(), d = try ExactRealRootDomain(field: f, using: &a)
        let x = try d.polynomials.variable(0, using: &a), source = try d.bind(x, using: &a)
        let all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        var observed = TerminalAdmission()
        _ = try d.isolate(source, in: all, limits: .init(maximumRoots: 1), using: &observed)
        var cancelled = TerminalAdmission(cancelAt: observed.checkpoints)
        do { _ = try d.isolate(source, in: all, limits: .init(maximumRoots: 1), using: &cancelled); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.scalar(.cancelled) {}
        var small = ExactScalarLedger(limits: try .init(work: observed.work, storageBytes: observed.storage - 1, valueDepth: 100, coefficientDepth: 100))
        do { _ = try d.isolate(source, in: all, limits: .init(maximumRoots: 1), using: &small); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.scalar(.resourceLimit(.storage)) {}
        var exact = ExactScalarLedger(limits: try .init(work: observed.work, storageBytes: observed.storage, valueDepth: 100, coefficientDepth: 100))
        try RootFixtures.require(d.isolate(source, in: all, limits: .init(maximumRoots: 1), using: &exact).roots.count == 1)
        print("PASS: terminal cancellation, atomic publication and exact storage boundary")
    }
    public static func retainedOwnersAndSelectedVariable() throws {
        func escaped() throws -> ExactRealRoot<ExactRationalScalarDomain> {
            var a = try ledger()
            let d = try ExactRealRootDomain(field: ExactRationalScalarDomain(), variableCount: 2, using: &a)
            let p = d.polynomials, v = try p.variable(1, using: &a)
            let source = try d.bind(v, variable: 1, using: &a)
            let all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
            return try d.isolate(source, in: all, limits: .init(maximumRoots: 1), using: &a).roots[0]
        }
        let root = try escaped()
        var a = try ledger()
        let d = try ExactRealRootDomain(retaining: root.source, using: &a)
        try RootFixtures.require(root.source.variable == 1 && root.source.original.variableCount == 2)
        try RootFixtures.require(d.sign(of: root.source, at: root, using: &a) == .zero)
        let x = try d.polynomials.variable(0, using: &a)
        let mixed = try d.polynomials.adding(x, root.source.original, using: &a)
        do { _ = try d.bind(mixed, variable: 1, using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.invalidSource {}
        func scalar() throws -> ExactAlgebraicScalar<ExactRationalScalarDomain> {
            var a = try ledger()
            let f = try ExactAlgebraicScalarDomain.base(field: ExactRationalScalarDomain(), maximumExtensionLevel: 1, using: &a)
            return try f.adjoin(FieldFixtures.root(f, degree: 2, right: f.integer(2, using: &a), &a), using: &a).generator
        }
        let value = try scalar(), field = try ExactAlgebraicScalarDomain(retaining: value, using: &a)
        try RootFixtures.require(field.sign(of: value, using: &a) == .positive)
        let raw = try ExactRationalScalarDomain().binary64(exactly: 0.5, using: &a)
        let half = try field.importingBase(raw, using: &a)
        try RootFixtures.require(field.compare(half, field.dividing(field.integer(1, using: &a), field.integer(2, using: &a), using: &a), using: &a) == .equal)
        print("PASS: retained owners, original variable map and exact base import")
    }
    public static func generalDegreeAndOddMultiplicity() throws {
        var a = try ledger()
        let f = ExactRationalScalarDomain(), d = try ExactRealRootDomain(field: f, using: &a), p = d.polynomials
        let x = try p.variable(0, using: &a), factor = try p.subtracting(x, p.constant(f.integer(1, using: &a), using: &a), using: &a)
        var law = factor
        for _ in 1..<5 { law = try p.multiplying(law, factor, using: &a) }
        let source = try d.bind(law, using: &a), all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        let result = try d.isolate(source, in: all, limits: .init(maximumRoots: 1), using: &a)
        try RootFixtures.require(result.roots.count == 1 && result.roots[0].multiplicity == 5)
        let one = try f.integer(1, using: &a), zero = try f.integer(0, using: &a)
        do { _ = try d.domain(lower: .finite(one), upper: .finite(zero), using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.invalidDomain {}
        do { _ = try d.bind(law, variable: 1, using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.invalidVariable {}
        do { _ = try ExactRealRootLimits(maximumRoots: -1); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.invalidDomain {}
        print("PASS: higher degree, odd multiplicity and invalid input failures")
    }
}
