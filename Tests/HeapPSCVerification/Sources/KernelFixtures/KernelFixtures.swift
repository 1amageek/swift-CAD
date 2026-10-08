import L0
@testable import L1
@testable import L1Fixtures

public enum KernelFixtures {
    typealias Field = ExactRationalScalarDomain
    typealias Domain = ExactPolynomialDomain<Field>
    typealias Polynomial = ExactPolynomial<Field>
    static func ledger() throws -> ExactScalarLedger {
        .init(limits: try .init(work: 200_000_000, storageBytes: 700_000_000, valueDepth: 400, coefficientDepth: 400))
    }
    static func check(_ valid: Bool) throws { if !valid { throw ExactPolynomialFailure.invalidCertificate } }
    static func reference<F: ExactScalarArithmetic & ExactScalarOrdering>(_ d: ExactPolynomialDomain<F>,
        _ first: ExactPolynomial<F>, _ second: ExactPolynomial<F>, _ f: F, _ a: inout ExactScalarLedger
    ) throws -> ExactPolynomial<F> {
        var terms: [ExactPolynomialTerm<F.Value>] = []
        for left in first.terms { for right in second.terms {
            let powers = try left.powers.indices.map { try ExactPolynomialAccess.exponent(left.powers[$0], right.powers[$0]) }
            terms.append(.init(powers: powers, coefficient: try f.multiplying(left.coefficient, right.coefficient, using: &a)))
        } }
        return try d.polynomial(terms: terms, using: &a)
    }
    public static func heap() throws {
        var a = try ledger()
        let f = Field(), d = try Domain(field: f, variableCount: 3, using: &a)
        for mode in 0..<12 {
            var left: [ExactPolynomialTerm<Field.Value>] = [], right: [ExactPolynomialTerm<Field.Value>] = []
            for i in 0..<7 {
                left.append(.init(powers: [i, (i * 3 + mode) % 5, mode % 3], coefficient: try f.integer(i % 2 == 0 ? i+1 : -i-1, using: &a)))
                right.append(.init(powers: [6-i, (i + mode) % 4, i % 3], coefficient: try f.integer(i+mode+1, using: &a)))
            }
            let p = try d.polynomial(terms: left, using: &a), q = try d.polynomial(terms: right, using: &a)
            let expected = try reference(d, p, q, f, &a)
            let actual = try d.multiplying(p, q, using: &a)
            try check(try d.equals(actual, expected, using: &a))
            try check(try d.equals(d.multiplying(q, p, using: &a), expected, using: &a))
        }
        let one = try f.integer(1, using: &a), minus = try f.integer(-1, using: &a)
        let x = try d.variable(0, using: &a), unit = try d.constant(one, using: &a)
        let sum = try d.adding(x, unit, using: &a), difference = try d.subtracting(x, unit, using: &a)
        let product = try d.multiplying(sum, difference, using: &a)
        let expected = try d.polynomial(terms: [.init(powers: [2,0,0], coefficient: one), .init(powers: [0,0,0], coefficient: minus)], using: &a)
        try check(try d.equals(product, expected, using: &a))
        let huge = try d.polynomial(terms: [.init(powers: [Int.max,0,0], coefficient: one), .init(powers: [0,0,0], coefficient: one)], using: &a)
        do { _ = try d.multiplying(huge, difference, using: &a); throw ExactPolynomialFailure.invalidCertificate }
        catch ExactPolynomialFailure.exponentOverflow { }
        for workLimit in [true,false] {
            var limit = ExactScalarLedger(limits: try .init(work: workLimit ? 0 : 100_000, storageBytes: workLimit ? 100_000 : 0, valueDepth: 400, coefficientDepth: 400))
            do { _ = try d.multiplying(sum, difference, using: &limit); throw ExactPolynomialFailure.invalidCertificate }
            catch ExactPolynomialFailure.scalar(.resourceLimit(let axis)) { try check(axis == (workLimit ? .work : .storage)) }
        }
        var trace = try L1PrimitiveFixtures.CallbackAdmission()
        _ = try d.multiplying(sum, difference, using: &trace)
        var cancelled = try L1PrimitiveFixtures.CallbackAdmission(); cancelled.cancelCheckpoint = trace.checkpoints
        do { _ = try d.multiplying(sum, difference, using: &cancelled); throw ExactPolynomialFailure.invalidCertificate }
        catch ExactPolynomialFailure.scalar(.cancelled) { }
        let algebraic = try L1PrimitiveFixtures.scalarField(), ad = try ExactPolynomialDomain(field: algebraic, variableCount: 2, using: &a)
        let root = try algebraic.generator(using: &a), ao = try algebraic.integer(1, using: &a)
        let ap = try ad.polynomial(terms: [.init(powers: [1,0], coefficient: root), .init(powers: [0,1], coefficient: ao)], using: &a)
        let aq = try ad.polynomial(terms: [.init(powers: [1,0], coefficient: root), .init(powers: [0,1], coefficient: try algebraic.negated(ao, using: &a))], using: &a)
        let actual = try ad.multiplying(ap, aq, using: &a)
        try check(try ad.equals(actual, reference(ad,ap,aq,algebraic,&a), using: &a))
        var shallow = ExactScalarLedger(limits: try .init(work: 100_000, storageBytes: 100_000, valueDepth: 400, coefficientDepth: 0))
        do { _ = try ad.multiplying(ap, aq, using: &shallow); throw ExactPolynomialFailure.invalidCertificate }
        catch ExactPolynomialFailure.scalar(.resourceLimit(.coefficientDepth)) { }
        print("PASS heap products, independent coefficients, overflow, algebraic depth, limits and final cancel")
    }
    public static func run() throws { try heap() }
}
