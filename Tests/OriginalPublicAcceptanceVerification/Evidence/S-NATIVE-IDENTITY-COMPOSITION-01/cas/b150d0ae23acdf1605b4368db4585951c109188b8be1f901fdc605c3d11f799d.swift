#if L2_ISOLATED_VERIFICATION
import L0
import L1
import DI0
#endif

public struct ExactRealRootDomain<F: ExactScalarArithmetic & ExactScalarOrdering>:
    ExactRealRootPreparing, ExactRealRootProducing, ExactRealRootQuerying {
    public typealias Field = F
    let context: ExactRealRootContext<F>
    init(context: ExactRealRootContext<F>) { self.context = context }
    public var polynomials: ExactPolynomialDomain<F> { context.input }
    public init<A: ExactScalarAdmission & ~Copyable>(retaining source: borrowing ExactRealRootSource<F>,
        using admission: inout A) throws(ExactRealRootFailure) {
        let source = copy source
        context = try ExactRootAccess.run(&admission, inherited: source.depth) { _ in source.context }
    }
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
            let interval: ExactParameterInterval<F.Value> = try ExactRootAccess.parameterDomain {
                () throws(ExactParameterDomainFailure) -> ExactParameterInterval<F.Value> in
                try .empty(depth: a.depth, using: &a)
            }
            return ExactRealRootInterval(retaining: interval)
        }
    }
    func interval(_ lo: ExactRealRootBound<F.Value>, _ hi: ExactRealRootBound<F.Value>,
        _ il: Bool, _ iu: Bool, _ a: inout ExactRootBorrowedAdmission) throws -> ExactRealRootInterval<F.Value> {
        let result: ExactParameterInterval<F.Value> = try ExactRootAccess.parameterDomain { () throws(ExactParameterDomainFailure) -> ExactParameterInterval<F.Value> in
            try .checked(field: context.field, lower: lo.domainBound, upper: hi.domainBound,
                includesLower: il, includesUpper: iu, depth: a.depth, using: &a)
        }
        // Scalar validation may discover retained coefficient depths. Preserve them
        // in the shared interval without resetting the exclusive caller admission.
        let retained = try ExactRootAccess.parameterDomain {
            () throws(ExactParameterDomainFailure) -> ExactParameterInterval<F.Value> in
            try result.retainingDepth(a.depth, using: &a)
        }
        return ExactRealRootInterval(retaining: retained)
    }
}
