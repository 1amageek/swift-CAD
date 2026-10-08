import L0
import L1
import L2

public enum CanonicalScalarFixtures {
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>

    static func query<A: ExactScalarAdmission & ~Copyable>(_ field: Field,
        _ lhs: Field.Value, _ rhs: Field.Value, _ a: inout A) throws(ExactScalarFailure) -> ExactSign {
        let sum = try field.adding(lhs, rhs, using: &a)
        let restored = try field.subtracting(sum, rhs, using: &a)
        let product = try field.multiplying(restored, rhs, using: &a)
        let quotient = try field.dividing(product, rhs, using: &a)
        guard try field.compare(quotient, lhs, using: &a) == .equal else { throw .invalidEvidence }
        return try field.sign(of: quotient, using: &a)
    }

    public static func verify() throws {
        var preparation = ExactScalarLedger(limits: try .init(work: 16_777_216,
            storageBytes: 200_000_000, valueDepth: 32, coefficientDepth: 32))
        let base = try Field.base(field: .init(), maximumExtensionLevel: 2, using: &preparation)
        let original = try FieldFixtures.root(base, degree: 2, right: base.integer(2, using: &preparation), &preparation)
        let rootDomain = try ExactRealRootDomain(retaining: original.source, using: &preparation)
        let root = try rootDomain.refine(original,
            maximumWidth: base.dividing(base.integer(1, using: &preparation), base.integer(16, using: &preparation), using: &preparation), using: &preparation)
        let extensionValue = try base.adjoin(root, using: &preparation)
        let field = extensionValue.domain, alpha = extensionValue.generator
        let p = rootDomain.polynomials
        let x = try p.variable(0, using: &preparation)
        let constants = [-3, 0, 4]
        for n in constants {
            let original = try base.integer(n, using: &preparation)
            let value = try extensionValue.embedding.importing(original, using: &preparation)
            let source = try rootDomain.bind(p.constant(original, using: &preparation), using: &preparation)
            try RootFixtures.require(field.sign(of: value, using: &preparation)
                == rootDomain.sign(of: source, at: root, using: &preparation))
            try RootFixtures.require(base.compare(original, base.integer(0, using: &preparation), using: &preparation)
                == (n == 0 ? .equal : n < 0 ? .less : .greater))
        }
        let square = try p.multiplying(x, x, using: &preparation)
        let zeroLaw = try p.subtracting(square, p.constant(base.integer(2, using: &preparation), using: &preparation), using: &preparation)
        let zero = try field.subtracting(field.multiplying(alpha, alpha, using: &preparation),
            field.integer(2, using: &preparation), using: &preparation)
        let checks = [(x, alpha), (zeroLaw, zero),
            (try p.negated(x, using: &preparation), try field.negated(alpha, using: &preparation))]
        for (law, value) in checks {
            let source = try rootDomain.bind(law, using: &preparation)
            try RootFixtures.require(field.sign(of: value, using: &preparation)
                == rootDomain.sign(of: source, at: root, using: &preparation))
        }
        let negative = try field.integer(-3, using: &preparation)
        var observed = TerminalAdmission()
        try RootFixtures.require(query(field, alpha, negative, &observed) == .positive)
        var exact = ExactScalarLedger(limits: try .init(work: observed.work,
            storageBytes: observed.storage, valueDepth: 32, coefficientDepth: 32))
        try RootFixtures.require(query(field, alpha, negative, &exact) == .positive)
        var work = ExactScalarLedger(limits: try .init(work: observed.work - 1,
            storageBytes: observed.storage, valueDepth: 32, coefficientDepth: 32))
        do { _ = try query(field, alpha, negative, &work); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.resourceLimit(.work) { }
        var storage = ExactScalarLedger(limits: try .init(work: observed.work,
            storageBytes: observed.storage - 1, valueDepth: 32, coefficientDepth: 32))
        do { _ = try query(field, alpha, negative, &storage); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.resourceLimit(.storage) { }
        var cancelled = TerminalAdmission(cancelAt: observed.checkpoints)
        do { _ = try query(field, alpha, negative, &cancelled); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.cancelled { }
        try RootFixtures.require(alpha.depth.coefficient > 0)
        var depth = ExactScalarLedger(limits: try .init(work: observed.work,
            storageBytes: observed.storage, valueDepth: 32, coefficientDepth: alpha.depth.coefficient - 1))
        do { _ = try field.sign(of: alpha, using: &depth); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.resourceLimit(.coefficientDepth) { }
        let sibling = try base.adjoin(root, using: &preparation)
        do { _ = try field.adding(alpha, sibling.generator, using: &preparation); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.incompatibleDomain { }
        do { _ = try field.dividing(zero, zero, using: &preparation); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.divisionByZero { }
        print("PASS: canonical scalar/public root signs, field identities, exact work/storage, depth, owners and final cancellation")
    }
}
