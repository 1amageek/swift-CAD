import L0
import L1

public enum L1PrimitiveFixtures {
    static func check(_ condition: Bool) { precondition(condition, "L1 behavioral assertion failed") }
    static func limits(work: Int = 50_000_000, storage: Int = 200_000_000,
        valueDepth: Int = 32, coefficientDepth: Int = 24) throws -> ExactScalarLimits {
        try .init(work: work, storageBytes: storage, valueDepth: valueDepth, coefficientDepth: coefficientDepth)
    }
    static func rejected(_ expected: String, _ body: () throws -> Void) throws {
        do { try body(); preconditionFailure("L1 incorrectly published success") }
        catch let failure as ExactPolynomialFailure {
            let actual: String
            switch failure {
            case .invalidVariableCount: actual = "variables"
            case .invalidVariable: actual = "variable"
            case .invalidExponent: actual = "exponent"
            case .exponentOverflow: actual = "overflow"
            case .countOverflow: actual = "count"
            case .incompatibleDomain: actual = "domain"
            case .zeroDivisor: actual = "zeroDivisor"
            case .notDivisible: actual = "remainder"
            case .undefinedMultiplicity: actual = "multiplicity"
            case .scalar(.resourceLimit(.work)): actual = "work"
            case .scalar(.resourceLimit(.storage)): actual = "storage"
            case .scalar(.resourceLimit(.valueDepth)): actual = "valueDepth"
            case .scalar(.resourceLimit(.coefficientDepth)): actual = "coefficientDepth"
            case .scalar(.cancelled): actual = "cancelled"
            case .scalar(.incompatibleDomain): actual = "scalarDomain"
            default: actual = "unexpected"
            }
            check(actual == expected)
        }
    }
    public static func rational() throws {
        let q = ExactRationalScalarDomain()
        var a = ExactScalarLedger(limits: try limits())
        let d = try ExactPolynomialDomain(field: q, variableCount: 3, using: &a)
        let one = try q.integer(1, using: &a), two = try q.integer(2, using: &a)
        let x = try d.variable(0, using: &a), y = try d.variable(1, using: &a), z = try d.variable(2, using: &a)
        let p = try d.polynomial(terms: [
            .init(powers: [1,0,0], coefficient: one), .init(powers: [1,0,0], coefficient: one),
            .init(powers: [0,1,0], coefficient: two), .init(powers: [0,1,0], coefficient: two.negated),
            .init(powers: [0,0,0], coefficient: .zero)], using: &a)
        check(p.terms.count == 1 && p.terms[0].powers == [1,0,0] && p.terms[0].coefficient == two)
        check(try d.equals(p, d.scaled(x, by: two, using: &a), using: &a))
        let xy = try d.adding(x, y, using: &a)
        let square = try d.multiplying(xy, xy, using: &a)
        check(square.terms.map { $0.powers } == [[2,0,0],[1,1,0],[0,2,0]])
        check(square.terms.map { $0.coefficient } == [one,two,one])
        check(try d.equals(d.differentiated(square, in: 0, using: &a), d.scaled(xy, by: two, using: &a), using: &a))
        let replacement = try d.substituted(square, with: [y, x, z], using: &a)
        check(try d.equals(square, replacement, using: &a))
        let evaluation = try d.evaluated(square, at: [q.integer(2, using: &a), q.integer(3, using: &a), .zero], using: &a)
        check(try evaluation.value == q.integer(25, using: &a))
        check(try d.isZero(d.subtracting(square, square, using: &a), using: &a))
        check(try d.degree(of: square, in: 0, using: &a) == 2)
        check(try d.degree(of: d.zero(using: &a), in: 0, using: &a) == nil)
        let other = try ExactPolynomialDomain(field: q, variableCount: 3, using: &a)
        try rejected("domain") { _ = try other.adding(x, other.zero(using: &a), using: &a) }
        check(try other.equals(other.importing(square, using: &a), other.multiplying(other.importing(xy, using: &a), other.importing(xy, using: &a), using: &a), using: &a))
        let empty = try ExactPolynomialDomain(field: q, variableCount: 0, using: &a)
        let c = try empty.constant(two, using: &a)
        check(c.terms[0].powers.isEmpty)
        check(try empty.evaluated(c, at: [], using: &a).value == two)
        try rejected("variable") { _ = try empty.variable(0, using: &a) }
    }
    struct RootAdmission: RationalAlgebraAdmitting {
        var work = 0
        var words = 0
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= 50_000_000 - work else { throw ExactScalarFailure.resourceLimit(.work) }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= 50_000_000 - words else { throw ExactScalarFailure.resourceLimit(.storage) }
            words += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard (0...24).contains(depth) else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        }
    }
    static func scalarField(axis: ExactScalarRootAxis = .coefficient, degree: Int = 2,
        refine: Bool = true) throws -> OriginalExactScalarDomain {
        var prep = RootAdmission()
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &prep)
        let p = try ExactBivariatePolynomial.monomial(u: degree, v: 0, coefficient: .one, usage: &prep)
            .subtracting(.constant(two, usage: &prep), usage: &prep)
        let roots = try ExactUnivariateRootIsolator().isolate(p, lower: .one, upper: two, maximumDepth: 32, usage: &prep)
        let issued = try ExactAlgebraicRealRoot(polynomial: p, isolation: roots[0], usage: &prep)
        let selected = try refine ? issued.refined(maximumWidth: .originalDouble(0x1p-4, usage: &prep),
            maximumDepth: 32, usage: &prep) : issued
        var a = ExactScalarLedger(limits: try limits())
        return try OriginalExactScalarDomain(root: selected, axis: axis,
            maximumValueDepth: 32, maximumCoefficientDepth: 24, using: &a)
    }
    public static func algebraic() throws {
        func escaped() throws -> ExactPolynomial<OriginalExactScalarDomain> {
            let f = try scalarField()
            var a = ExactScalarLedger(limits: try limits())
            let d = try ExactPolynomialDomain(field: f, variableCount: 2, using: &a)
            let root = try f.generator(using: &a)
            let one = try f.integer(1, using: &a)
            return try d.polynomial(terms: [.init(powers: [1,0], coefficient: root),
                .init(powers: [0,0], coefficient: one)], using: &a)
        }
        let p = try escaped()
        var a = ExactScalarLedger(limits: try limits())
        let d = try ExactPolynomialDomain(retaining: p, using: &a)
        let f = try OriginalExactScalarDomain(retaining: p.terms[0].coefficient,
            maximumValueDepth: 32, maximumCoefficientDepth: 24, using: &a)
        let root = try f.generator(using: &a), one = try f.integer(1, using: &a)
        let value = try d.evaluated(p, at: [root, one], using: &a)
        check(try f.compare(value.value, f.integer(3, using: &a), using: &a) == .equal)
        let zero = try d.subtracting(p, p, using: &a)
        check(zero.terms.isEmpty && zero.depth.coefficient > 0 && zero.depth.value == 0)
        var shallow = ExactScalarLedger(limits: try limits(coefficientDepth: 0))
        try rejected("coefficientDepth") { _ = try d.isZero(zero, using: &shallow) }
        check(shallow.work == 0 && shallow.storageBytes == 0)
        var cancelledTerms = ExactScalarLedger(limits: try limits())
        let other = try scalarField()
        try rejected("scalarDomain") {
            _ = try d.constant(other.integer(0, using: &cancelledTerms), using: &cancelledTerms)
        }
        let parameterField = try scalarField(axis: .value)
        let parameterDomain = try ExactPolynomialDomain(field: parameterField, variableCount: 1, using: &a)
        let parameter = try parameterDomain.constant(parameterField.generator(using: &a), using: &a)
        let parameterZero = try parameterDomain.subtracting(parameter, parameter, using: &a)
        check(parameterZero.depth.value > 0 && parameterZero.depth.coefficient == 0)
        var noValueDepth = ExactScalarLedger(limits: try limits(valueDepth: 0))
        try rejected("valueDepth") { _ = try parameterDomain.isZero(parameterZero, using: &noValueDepth) }
        let empty = try d.differentiated(p, in: 1, using: &a)
        check(empty.terms.isEmpty && empty.depth.coefficient >= p.depth.coefficient)
        check(try d.isZero(d.substituted(empty, with: [p,p], using: &a), using: &a))
        // Comparing sqrt(2) with 3/2 requires actual coefficient-root refinement.
        let unrefined = try scalarField(refine: false)
        let unrefinedDomain = try ExactPolynomialDomain(field: unrefined, variableCount: 1, using: &a)
        let unrefinedRoot = try unrefined.generator(using: &a)
        let probe = try unrefinedDomain.constant(unrefinedRoot, using: &a)
        let rational = try unrefined.binary64(exactly: 1.5, using: &a)
        var visits = try CallbackAdmission()
        _ = try unrefinedDomain.subtracting(probe,
            unrefinedDomain.constant(rational, using: &visits), using: &visits)
        check(visits.visitCalls > 0)
        var stopped = try CallbackAdmission(); stopped.cancelVisit = 1
        try rejected("cancelled") {
            _ = try unrefinedDomain.subtracting(probe,
                unrefinedDomain.constant(rational, using: &stopped), using: &stopped)
        }
    }
    struct CallbackAdmission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var checkpoints = 0
        var workCalls = 0
        var storageCalls = 0
        var visitCalls = 0
        var cancelVisit: Int?
        var cancelCheckpoint: Int?
        var cancelWork: Int?
        var cancelStorage: Int?
        init() throws { ledger = ExactScalarLedger(limits: try limits()) }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints == cancelCheckpoint { ledger.cancel() }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
            workCalls += 1; try ledger.consumeWork(units)
            if workCalls == cancelWork { ledger.cancel() }
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            storageCalls += 1; try ledger.retainStorage(bytes: bytes)
            if storageCalls == cancelStorage { ledger.cancel() }
        }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try ledger.visitCell(axis: axis, depth: depth)
            visitCalls += 1
            if visitCalls == cancelVisit { ledger.cancel() }
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
    }
    public static func failures() throws {
        let f = ExactRationalScalarDomain()
        var a = ExactScalarLedger(limits: try limits())
        let d = try ExactPolynomialDomain(field: f, variableCount: 1, using: &a)
        let x = try d.variable(0, using: &a)
        try rejected("variables") { _ = try ExactPolynomialDomain(field: f, variableCount: -1, using: &a) }
        try rejected("exponent") { _ = try d.polynomial(terms: [.init(powers: [-1], coefficient: .one)], using: &a) }
        try rejected("exponent") { _ = try d.polynomial(terms: [.init(powers: [], coefficient: .one)], using: &a) }
        try rejected("variables") { _ = try d.evaluated(x, at: [], using: &a) }
        let extreme = try d.polynomial(terms: [.init(powers: [Int.max], coefficient: .one)], using: &a)
        try rejected("overflow") { _ = try d.multiplying(extreme, x, using: &a) }
        var work = ExactScalarLedger(limits: try limits(work: 0))
        try rejected("work") { _ = try d.zero(using: &work) }
        var storage = ExactScalarLedger(limits: try limits(storage: 0))
        try rejected("storage") { _ = try d.multiplying(x, x, using: &storage) }
        check(storage.work > 0 && storage.storageBytes == 0)
        var cancellation = ExactScalarLedger(limits: try limits())
        cancellation.cancel()
        try rejected("cancelled") { _ = try d.isZero(x, using: &cancellation) }
        check(cancellation.work == 0 && cancellation.storageBytes == 0)
        var baseline = try CallbackAdmission()
        _ = try d.multiplying(x, x, using: &baseline)
        var final = try CallbackAdmission(); final.cancelCheckpoint = baseline.checkpoints
        try rejected("cancelled") { _ = try d.multiplying(x, x, using: &final) }
        var lastStorage = try CallbackAdmission(); lastStorage.cancelStorage = baseline.storageCalls
        try rejected("cancelled") { _ = try d.multiplying(x, x, using: &lastStorage) }
        var lastWork = try CallbackAdmission(); lastWork.cancelWork = baseline.workCalls
        try rejected("cancelled") { _ = try d.multiplying(x, x, using: &lastWork) }
        check(lastStorage.ledger.storageBytes > 0 && lastWork.ledger.work > 0)
        var cumulative = ExactScalarLedger(limits: try limits(work: 1))
        _ = try d.zero(using: &cumulative)
        try rejected("work") { _ = try d.zero(using: &cumulative) }
        check(cumulative.work == 1)
    }
}
