import L0
import L1
import L2

public enum RepeatedDivisionFixtures {
    static func admission(work: Int = 10_000_000, storage: Int = 100_000_000,
        valueDepth: Int = 128, coefficientDepth: Int = 32) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: storage, valueDepth: valueDepth, coefficientDepth: coefficientDepth))
    }
    static func verify<F: ExactScalarArithmetic & ExactScalarOrdering>(field: F, divisor: F.Value,
        expectSavings: Bool) throws {
        var setup = try admission()
        let zero = try field.integer(0, using: &setup), one = try field.integer(1, using: &setup)
        let values = [zero, one, try field.integer(-3, using: &setup)]
        for count in 1...3 {
            let selected = Array(values.prefix(count))
            var reference = try admission(), optimized = try admission()
            try reference.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: F.Value.self))
            var expected: [F.Value] = []
            for value in selected {
                try reference.consumeWork(1)
                expected.append(try field.dividing(value, divisor, using: &reference))
            }
            let actual = try field.dividing(selected, by: divisor, using: &optimized)
            try DomainFixtures.require(actual.count == count)
            for i in actual.indices {
                try DomainFixtures.require(field.compare(actual[i], expected[i], using: &setup) == .equal)
            }
            if count == 3 {
                if expectSavings {
                    try DomainFixtures.require(optimized.work < reference.work && optimized.storageBytes < reference.storageBytes)
                } else {
                    try DomainFixtures.require(optimized.work == reference.work && optimized.storageBytes == reference.storageBytes)
                }
                var workDenied = try admission(work: optimized.work - 1)
                do { _ = try field.dividing(selected, by: divisor, using: &workDenied); throw ExactScalarFailure.invalidEvidence }
                catch ExactScalarFailure.resourceLimit(.work) {}
                var storageDenied = try admission(storage: optimized.storageBytes - 1)
                do { _ = try field.dividing(selected, by: divisor, using: &storageDenied); throw ExactScalarFailure.invalidEvidence }
                catch ExactScalarFailure.resourceLimit(.storage) {}
                if optimized.valueDepth > 0 {
                    var denied = try admission(valueDepth: optimized.valueDepth - 1)
                    do { _ = try field.dividing(selected, by: divisor, using: &denied); throw ExactScalarFailure.invalidEvidence }
                    catch ExactScalarFailure.resourceLimit(.valueDepth) {}
                }
                if optimized.coefficientDepth > 0 {
                    var denied = try admission(coefficientDepth: optimized.coefficientDepth - 1)
                    do { _ = try field.dividing(selected, by: divisor, using: &denied); throw ExactScalarFailure.invalidEvidence }
                    catch ExactScalarFailure.resourceLimit(.coefficientDepth) {}
                }
            }
        }
        let negative = try field.negated(divisor, using: &setup)
        let negativeResults = try field.dividing(values, by: negative, using: &setup)
        for i in values.indices {
            try DomainFixtures.require(field.compare(negativeResults[i], field.dividing(values[i], negative, using: &setup), using: &setup) == .equal)
        }
        do { _ = try field.dividing(values, by: zero, using: &setup); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.divisionByZero {}
        var empty = try admission(work: 0, storage: 0, valueDepth: 0, coefficientDepth: 0)
        try DomainFixtures.require(field.dividing([], by: zero, using: &empty).isEmpty)
        var observed = try TerminalAdmission(valueDepth: 128, coefficientDepth: 32)
        _ = try field.dividing(values, by: divisor, using: &observed)
        var cancelled = try TerminalAdmission(valueDepth: 128, coefficientDepth: 32)
        cancelled.cancelAt = observed.checks
        do { _ = try field.dividing(values, by: divisor, using: &cancelled); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.cancelled {}
        var entryCancelled = try admission(); entryCancelled.cancel()
        do { _ = try field.dividing(values, by: divisor, using: &entryCancelled); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.cancelled {}
    }
    public static func rational() throws {
        var a = try admission(); let field = ExactRationalScalarDomain()
        try verify(field: field, divisor: field.integer(5, using: &a), expectSavings: false)
    }
    public static func localInverse() throws {
        typealias F = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
        var a = try admission()
        let base = try F.base(field: .init(), maximumExtensionLevel: 2, using: &a)
        let roots = try ExactRealRootDomain(field: base, using: &a), p = roots.polynomials
        let x = try p.variable(0, using: &a), square = try p.multiplying(x, x, using: &a)
        let q2 = try p.subtracting(square, p.constant(base.integer(2, using: &a), using: &a), using: &a)
        let q3 = try p.subtracting(square, p.constant(base.integer(3, using: &a), using: &a), using: &a)
        let q5 = try p.subtracting(square, p.constant(base.integer(5, using: &a), using: &a), using: &a)
        let original = try roots.bind(p.multiplying(p.multiplying(q2, q3, using: &a), q5, using: &a), using: &a)
        let selected = try roots.domain(lower: .finite(base.integer(1, using: &a)),
            upper: .finite(base.dividing(base.integer(3, using: &a), base.integer(2, using: &a), using: &a)), using: &a)
        let root = try roots.isolate(original, in: selected, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extensionField = try base.adjoin(root, using: &a), field = extensionField.domain
        let alpha = extensionField.generator, one = try field.integer(1, using: &a)
        let alphaSquare = try field.multiplying(alpha, alpha, using: &a)
        let denominator = try field.subtracting(alphaSquare, field.integer(3, using: &a), using: &a)
        let secondDenominator = try field.subtracting(alphaSquare, field.integer(5, using: &a), using: &a)
        let prior = try field.dividing(one, secondDenominator, using: &a)
        let values = [try field.integer(0, using: &a), one, prior]
        let actual = try field.dividing(values, by: denominator, using: &a)
        for i in values.indices {
            let expected = try field.dividing(values[i], denominator, using: &a)
            try DomainFixtures.require(field.compare(actual[i], expected, using: &a) == .equal)
        }
        guard let proof = actual[1].calculation else { throw ExactScalarFailure.invalidEvidence }
        try DomainFixtures.require(proof.originalRoot.ordinal == root.ordinal)
        try DomainFixtures.require(proof.selectedRoot.multiplicity == root.multiplicity)
        try DomainFixtures.require(alpha.calculation == nil && root.source.original.terms.first!.powers[0] == 6)
        let zeroAtRoot = try field.subtracting(alphaSquare, field.integer(2, using: &a), using: &a)
        do { _ = try field.dividing(values, by: zeroAtRoot, using: &a); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.divisionByZero {}
    }
}
