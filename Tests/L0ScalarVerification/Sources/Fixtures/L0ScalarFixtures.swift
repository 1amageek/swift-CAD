import L0

public enum L0ScalarFixtures {
    static func verify(_ condition: Bool, _ message: String = "L0 behavioral assertion failed") { precondition(condition, message) }
    static func limits(work: Int = 50_000_000, storage: Int = 200_000_000,
        valueDepth: Int = 32, coefficientDepth: Int = 24) throws(ExactScalarFailure) -> ExactScalarLimits {
        try .init(work: work, storageBytes: storage, valueDepth: valueDepth, coefficientDepth: coefficientDepth)
    }
    public static func runAll() throws {
        try rationals(); print("PASS: rational source bits and field operations")
        try algebraic(); print("PASS: retained algebraic source, order and lifetime")
        try failures(); print("PASS: independent limits, explicit failures and cancellation")
        try L0PayloadFixtures.run()
        print("PASS: typed payload admission and cubic-root sign resource boundaries")
        try L0FiberStorageFixtures.run()
        print("PASS: typed monomial and fiber storage, exact roots and retained identities")
    }

    public static func rationals() throws {
        let field = ExactRationalScalarDomain()
        var budget = ExactScalarLedger(limits: try limits())
        let zero = try field.binary64(exactly: -0.0, using: &budget)
        let positiveZero = try field.binary64(exactly: 0.0, using: &budget)
        verify(zero == .zero && positiveZero == zero)
        let tiny = try field.binary64(exactly: Double.leastNonzeroMagnitude, using: &budget)
        verify(tiny.canonicalSign == 1 && tiny.canonicalNumeratorWords == [1])
        verify(tiny.canonicalDenominatorWords.count == 34 && tiny.canonicalDenominatorWords.last == 1 << 18)
        let decimal = try field.binary64(exactly: 0.1, using: &budget)
        verify(decimal.canonicalNumeratorWords == [0xcccccccd, 0xccccc])
        verify(decimal.canonicalDenominatorWords == [0, 1 << 23])
        let signed = try field.integer(Int64.min, using: &budget)
        verify(signed.canonicalSign == -1 && signed.canonicalNumeratorWords == [0, 0x80000000])
        let unsigned = try field.integer(UInt64.max, using: &budget)
        verify(unsigned.canonicalSign == 1 && unsigned.canonicalNumeratorWords == [UInt32.max, UInt32.max])
        let a = try field.canonical(sign: 1, numerator: [3], denominator: [7], using: &budget)
        let b = try field.canonical(sign: 1, numerator: [5], denominator: [11], using: &budget)
        let sum = try field.adding(a, b, using: &budget)
        verify(sum.canonicalNumeratorWords == [68] && sum.canonicalDenominatorWords == [77])
        let difference = try field.subtracting(a, b, using: &budget)
        verify(difference.canonicalSign == -1 && difference.canonicalNumeratorWords == [2] && difference.canonicalDenominatorWords == [77])
        let product = try field.multiplying(a, b, using: &budget)
        verify(product.canonicalNumeratorWords == [15] && product.canonicalDenominatorWords == [77])
        let quotient = try field.dividing(a, b, using: &budget)
        verify(quotient.canonicalNumeratorWords == [33] && quotient.canonicalDenominatorWords == [35])
        verify(try exactEquality(field, field.subtracting(sum, b, using: &budget), a, using: &budget))
        verify(try exactZero(field, field.adding(a, field.negated(a, using: &budget), using: &budget), using: &budget))
        verify(try field.compare(a, b, using: &budget) == .less)
        verify(try field.sign(of: signed, using: &budget) == .negative)
        verify(try field.importing(sum, using: &budget) == sum)
        let near = try field.binary64(exactly: 0x1p-60, using: &budget)
        let one = try field.integer(1, using: &budget)
        verify(1.0 + 0x1p-60 == 1.0)
        verify(try field.compare(field.adding(one, near, using: &budget), one, using: &budget) == .greater)
        try multiwordGoldens(field, using: &budget)
        verify(budget.work > 0 && budget.storageBytes > 0)
    }

    /// Root preparation executes the original scalar issuer under its finite ledger.
    struct RootPreparation: RationalAlgebraAdmitting {
        var work = 0
        var storage = 0
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= 50_000_000 - work else { throw ExactScalarFailure.resourceLimit(.work) }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= 50_000_000 - storage else { throw ExactScalarFailure.resourceLimit(.storage) }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard (0...24).contains(depth) else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        }
    }
    static func root(negative: Bool = false) throws -> ExactAlgebraicRealRoot {
        var usage = RootPreparation()
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &usage)
        let polynomial = try ExactBivariatePolynomial.monomial(u: 2, v: 0, coefficient: .one, usage: &usage)
            .subtracting(.constant(two, usage: &usage), usage: &usage)
        let lower = negative ? two.negated : .one
        let upper = negative ? ExactRationalCoefficient.one.negated : two
        let brackets = try ExactUnivariateRootIsolator().isolate(polynomial, lower: lower, upper: upper, maximumDepth: 32, usage: &usage)
        verify(brackets.count == 1)
        let selected = try ExactAlgebraicRealRoot(polynomial: polynomial, isolation: brackets[0], usage: &usage)
        let width = try ExactRationalCoefficient.originalDouble(0x1p-4, usage: &usage)
        let retained = try selected.refined(maximumWidth: width, maximumDepth: 32, usage: &usage)
        verify(retained.isolation.isolationDepth > 0)
        return retained
    }
    public static func algebraic() throws {
        var budget = ExactScalarLedger(limits: try limits())
        let selected = try root()
        let field = try OriginalExactScalarDomain(root: selected, axis: .value,
            maximumValueDepth: 32, maximumCoefficientDepth: 24, using: &budget)
        let x = try field.generator(using: &budget)
        var coefficientOnly = ExactScalarLedger(limits: try limits(valueDepth: 0))
        let coefficientField = try OriginalExactScalarDomain(root: selected, axis: .coefficient,
            maximumValueDepth: 0, maximumCoefficientDepth: 24, using: &coefficientOnly)
        let coefficientValue = try coefficientField.generator(using: &coefficientOnly)
        verify(try coefficientField.sign(of: coefficientValue, using: &coefficientOnly) == .positive)
        verify(coefficientOnly.valueDepth == 0 && coefficientOnly.coefficientDepth > 0)
        let one = try field.integer(1, using: &budget)
        let two = try field.integer(2, using: &budget)
        let zero = try field.integer(0, using: &budget)
        try expect(.zeroDivision) { _ = try field.dividing(x, zero, using: &budget) }
        var noAlgebraicWork = ExactScalarLedger(limits: try limits(work: 0))
        try expect(.resource(.work)) { _ = try field.compare(x, one, using: &noAlgebraicWork) }
        var noAlgebraicStorage = ExactScalarLedger(limits: try limits(storage: 0))
        try expect(.resource(.storage)) { _ = try field.adding(x, one, using: &noAlgebraicStorage) }
        verify(noAlgebraicStorage.work > 0 && noAlgebraicStorage.storageBytes == 0)
        var cancelledAlgebraic = ExactScalarLedger(limits: try limits())
        cancelledAlgebraic.cancel()
        try expect(.cancelled) { _ = try field.sign(of: x, using: &cancelledAlgebraic) }
        verify(cancelledAlgebraic.work == 0 && cancelledAlgebraic.storageBytes == 0)
        var algebraicBaseline = try CallbackAdmission()
        _ = try field.adding(x, one, using: &algebraicBaseline)
        var algebraicTerminal = try CallbackAdmission()
        algebraicTerminal.cancelOnCheckpoint = algebraicBaseline.checkpointCalls
        try expect(.cancelled) { _ = try field.adding(x, one, using: &algebraicTerminal) }
        verify(try field.sign(of: x, using: &budget) == .positive)
        verify(try exactEquality(field, field.multiplying(x, x, using: &budget), two, using: &budget))
        let first = try field.adding(x, one, using: &budget)
        let second = try field.subtracting(x, one, using: &budget)
        verify(try exactEquality(field, field.multiplying(first, second, using: &budget), one, using: &budget))
        verify(try exactEquality(field, field.dividing(one, first, using: &budget), second, using: &budget))
        let opposite = try field.negated(x, using: &budget)
        verify(try field.sign(of: opposite, using: &budget) == .negative)
        verify(try field.compare(opposite, x, using: &budget) == .less)
        let tiny = try field.binary64(exactly: 0x1p-60, using: &budget)
        verify(try field.compare(field.adding(x, tiny, using: &budget), x, using: &budget) == .greater)
        let other = try OriginalExactScalarDomain(root: selected, axis: .value,
            maximumValueDepth: 32, maximumCoefficientDepth: 24, using: &budget)
        let unrelated = try other.generator(using: &budget)
        try expect(.domain) { _ = try field.adding(x, unrelated, using: &budget) }
        try expect(.domain) { _ = try field.adding(unrelated, x, using: &budget) }
        try expect(.domain) { _ = try field.compare(x, unrelated, using: &budget) }
        try expect(.domain) { _ = try field.importing(unrelated, using: &budget) }
        verify(try exactEquality(field, field.importing(other.integer(1, using: &budget), using: &budget), one, using: &budget))
        var reuse = ExactScalarLedger(limits: try limits(storage: 0))
        let reused = try field.importing(x, using: &reuse)
        verify(reused.depth == x.depth && reuse.storageBytes == 0)
        let negative = try OriginalExactScalarDomain(root: root(negative: true), axis: .value,
            maximumValueDepth: 32, maximumCoefficientDepth: 24, using: &budget)
        verify(try negative.sign(of: negative.generator(using: &budget), using: &budget) == .negative)

        // Only the result survives this scope; its domain, root and coefficients must survive too.
        func retainedResult() throws -> OriginalExactScalar {
            var admission = ExactScalarLedger(limits: try limits())
            let temporary = try OriginalExactScalarDomain(root: root(), axis: .coefficient,
                maximumValueDepth: 32, maximumCoefficientDepth: 24, using: &admission)
            return try temporary.adding(temporary.generator(using: &admission),
                temporary.integer(1, using: &admission), using: &admission)
        }
        let retained = try retainedResult()
        verify(retained.depth.coefficient > 0 && retained.depth.value == 0)
        let restored = try OriginalExactScalarDomain(retaining: retained, maximumValueDepth: 32,
            maximumCoefficientDepth: 24, using: &budget)
        verify(try restored.sign(of: retained, using: &budget) == .positive)
        verify(try restored.compare(retained, restored.integer(2, using: &budget), using: &budget) == .greater)
        let y = try restored.subtracting(retained, restored.integer(1, using: &budget), using: &budget)
        verify(try exactEquality(restored, restored.multiplying(y, y, using: &budget), restored.integer(2, using: &budget), using: &budget))
        var tooShallow = ExactScalarLedger(limits: try limits(coefficientDepth: 0))
        try expect(.resource(.coefficientDepth)) { _ = try restored.integer(0, using: &tooShallow) }
        verify(tooShallow.work == 0 && tooShallow.storageBytes == 0)
        var lowValue = ExactScalarLedger(limits: try limits(valueDepth: 0))
        try expect(.resource(.valueDepth)) { _ = try field.integer(0, using: &lowValue) }
        verify(lowValue.work == 0 && lowValue.storageBytes == 0)
    }

    enum Expected {
        case resource(ExactResource), cancelled, source, evidence, domain, zeroDivision, overflow, unsupported
    }
    static func expect(_ expected: Expected, _ body: () throws -> Void) throws {
        do { try body(); preconditionFailure("L0 published a result instead of the required failure") }
        catch let failure as ExactScalarFailure {
            let matches: Bool
            switch (expected, failure) {
            case (.resource(let wanted), .resourceLimit(let actual)): matches = wanted == actual
            case (.cancelled, .cancelled), (.source, .invalidSource), (.evidence, .invalidEvidence),
                 (.domain, .incompatibleDomain), (.zeroDivision, .divisionByZero), (.overflow, .countOverflow), (.unsupported, .unsupportedRepresentation): matches = true
            default: matches = false
            }
            verify(matches, "L0 returned the wrong typed failure")
        }
    }
    struct CallbackAdmission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var workCalls = 0
        var storageCalls = 0
        var depthCalls = 0
        var checkpointCalls = 0
        var cancelOnWork: Int?
        var cancelOnStorage: Int?
        var cancelOnDepth: Int?
        var cancelOnCheckpoint: Int?
        init() throws { ledger = ExactScalarLedger(limits: try limits()) }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpointCalls += 1
            if checkpointCalls == cancelOnCheckpoint { ledger.cancel() }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
            workCalls += 1; try ledger.consumeWork(units)
            if workCalls == cancelOnWork { ledger.cancel() }
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            storageCalls += 1; try ledger.retainStorage(bytes: bytes)
            if storageCalls == cancelOnStorage { ledger.cancel() }
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            depthCalls += 1; try ledger.admitDepth(value: value, coefficient: coefficient)
            if depthCalls == cancelOnDepth { ledger.cancel() }
        }
    }
    public static func failures() throws {
        let field = ExactRationalScalarDomain()
        var preparing = ExactScalarLedger(limits: try limits())
        let a = try field.canonical(sign: 1, numerator: [3], denominator: [7], using: &preparing)
        let rationalOwner = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 24, using: &preparing)
        try expect(.unsupported) { _ = try rationalOwner.generator(using: &preparing) }
        let b = try field.canonical(sign: 1, numerator: [5], denominator: [11], using: &preparing)
        try expect(.source) { _ = try field.binary64(exactly: .infinity, using: &preparing) }
        try expect(.source) { _ = try field.binary64(exactly: .nan, using: &preparing) }
        try expect(.source) { _ = try field.canonical(sign: 1, numerator: [2], denominator: [4], using: &preparing) }
        try expect(.source) { _ = try field.canonical(sign: 1, numerator: [1], denominator: [], using: &preparing) }
        try expect(.zeroDivision) { _ = try field.dividing(a, .zero, using: &preparing) }
        var noWork = ExactScalarLedger(limits: try limits(work: 0))
        try expect(.resource(.work)) { _ = try field.compare(a, b, using: &noWork) }
        verify(noWork.work == 0 && noWork.storageBytes == 0)
        var noStorage = ExactScalarLedger(limits: try limits(storage: 0))
        try expect(.resource(.storage)) { _ = try field.adding(a, b, using: &noStorage) }
        verify(noStorage.work > 0 && noStorage.storageBytes == 0)
        verify(try field.compare(a, b, using: &preparing) == .less)
        var exhausted = ExactScalarLedger(limits: try limits(work: 1))
        _ = try field.integer(0, using: &exhausted)
        try expect(.resource(.work)) { _ = try field.integer(0, using: &exhausted) }
        verify(exhausted.work == 1)
        var cancelled = ExactScalarLedger(limits: try limits())
        cancelled.cancel()
        try expect(.cancelled) { _ = try field.integer(0, using: &cancelled) }
        verify(cancelled.work == 0 && cancelled.storageBytes == 0)
        var overflow = ExactScalarLedger(limits: try limits(work: Int.max, storage: Int.max))
        try overflow.consumeWork(Int.max)
        try expect(.overflow) { try overflow.consumeWork(1) }
        verify(overflow.work == Int.max)
        try overflow.retainStorage(bytes: Int.max)
        try expect(.overflow) { try overflow.retainStorage(bytes: 1) }
        verify(overflow.storageBytes == Int.max)

        // Measure a stable operation once, then reject publication from its final callbacks.
        var baseline = try CallbackAdmission()
        _ = try field.adding(a, b, using: &baseline)
        var lastWork = try CallbackAdmission(); lastWork.cancelOnWork = baseline.workCalls
        try expect(.cancelled) { _ = try field.adding(a, b, using: &lastWork) }
        var lastStorage = try CallbackAdmission(); lastStorage.cancelOnStorage = baseline.storageCalls
        try expect(.cancelled) { _ = try field.adding(a, b, using: &lastStorage) }
        var terminal = try CallbackAdmission(); terminal.cancelOnCheckpoint = baseline.checkpointCalls
        try expect(.cancelled) { _ = try field.adding(a, b, using: &terminal) }
        var initialDepth = try CallbackAdmission(); initialDepth.cancelOnDepth = 1
        try expect(.cancelled) { _ = try field.integer(0, using: &initialDepth) }
        verify(lastWork.ledger.work > 0 && lastStorage.ledger.storageBytes > 0)
        for fast in 0..<7 {
            var admission = try CallbackAdmission(); admission.cancelOnWork = 1
            try expect(.cancelled) {
                switch fast {
                case 0: _ = try field.integer(0, using: &admission)
                case 1: _ = try field.binary64(exactly: -0.0, using: &admission)
                case 2: _ = try field.adding(.zero, a, using: &admission)
                case 3: _ = try field.multiplying(.zero, a, using: &admission)
                case 4: _ = try field.dividing(a, .one, using: &admission)
                case 5: _ = try field.sign(of: .zero, using: &admission)
                default: _ = try field.importing(a, using: &admission)
                }
            }
        }
    }
}
