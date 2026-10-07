#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactRealRootDomain<F: ExactScalarArithmetic & ExactScalarOrdering>:
    ExactRealRootPreparing, ExactRealRootProducing, ExactRealRootQuerying {
    public typealias Field = F
    let context: ExactRealRootContext<F>
    public var polynomials: ExactPolynomialDomain<F> { context.input }
    public init<A: ExactScalarAdmission & ~Copyable>(field: F, variableCount: Int = 1,
        using admission: inout A) throws(ExactRealRootFailure) {
        context = try ExactRootAccess.run(&admission) { usage in
            guard variableCount > 0 else { throw ExactRealRootFailure.invalidVariable }
            let input = try ExactPolynomialDomain(field: field, variableCount: variableCount, using: &usage)
            let univariate = try ExactPolynomialDomain(field: field, variableCount: 1, using: &usage)
            try ExactRootAccess.owner((F, ExactPolynomialDomain<F>, ExactPolynomialDomain<F>, ExactScalarDepth).self, &usage)
            return ExactRealRootContext(field: field, input: input, univariate: univariate, depth: usage.depth)
        }
    }
    func require(_ source: ExactRealRootSource<F>, _ a: inout ExactRootBorrowedAdmission) throws {
        guard source.context === context else { throw ExactRealRootFailure.incompatibleDomain }
        try ExactRootAccess.admit(source.depth, &a)
    }
    public func bind<A: ExactScalarAdmission & ~Copyable>(_ polynomial: borrowing ExactPolynomial<F>,
        variable: Int = 0, refinementAxis: ExactScalarRootAxis = .value, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSource<F> {
        try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            _ = try polynomials.isZero(polynomial, using: &a)
            guard variable >= 0, variable < polynomial.variableCount else { throw ExactRealRootFailure.invalidVariable }
            try ExactRootAccess.storage(polynomial.termCount, ExactPolynomialTerm<F.Value>.self, &a)
            var terms: [ExactPolynomialTerm<F.Value>] = []; terms.reserveCapacity(polynomial.termCount)
            for term in polynomial.terms {
                try a.consumeWork(polynomial.variableCount)
                for i in term.powers.indices where i != variable {
                    guard term.powers[i] == 0 else { throw ExactRealRootFailure.invalidSource }
                }
                try ExactRootAccess.storage(1, Int.self, &a)
                terms.append(.init(powers: [term.powers[variable]], coefficient: term.coefficient))
            }
            let law = try context.univariate.polynomial(terms: terms, using: &a)
            return ExactRealRootSource(context: context, original: copy polynomial, variable: variable,
                refinementAxis: refinementAxis, law: law, depth: a.depth)
        }
    }
    public func domain<A: ExactScalarAdmission & ~Copyable>(lower: ExactRealRootBound<F.Value>,
        upper: ExactRealRootBound<F.Value>, includesLower: Bool = true, includesUpper: Bool = true,
        using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRootInterval<F.Value> {
        try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try interval(lower, upper, includesLower, includesUpper, &a)
        }
    }
    public func emptyDomain<A: ExactScalarAdmission & ~Copyable>(using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootInterval<F.Value> {
        try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            ExactRealRootInterval(lower: .negativeInfinity, upper: .positiveInfinity,
                includesLower: false, includesUpper: false, isEmpty: true, depth: a.depth)
        }
    }
    func interval(_ lo: ExactRealRootBound<F.Value>, _ hi: ExactRealRootBound<F.Value>,
        _ il: Bool, _ iu: Bool, _ a: inout ExactRootBorrowedAdmission) throws -> ExactRealRootInterval<F.Value> {
        if case .positiveInfinity = lo { throw ExactRealRootFailure.invalidDomain }
        if case .negativeInfinity = hi { throw ExactRealRootFailure.invalidDomain }
        var empty = false
        if case .finite(let value) = lo { _ = try context.field.sign(of: value, using: &a) }
        if case .finite(let value) = hi { _ = try context.field.sign(of: value, using: &a) }
        if case .finite(let l) = lo, case .finite(let h) = hi {
            let order = try context.field.compare(l, h, using: &a)
            guard order != .greater else { throw ExactRealRootFailure.invalidDomain }
            empty = order == .equal && !(il && iu)
        }
        return ExactRealRootInterval(lower: lo, upper: hi,
            includesLower: { if case .finite = lo { return il }; return false }(),
            includesUpper: { if case .finite = hi { return iu }; return false }(), isEmpty: empty, depth: a.depth)
    }
}
