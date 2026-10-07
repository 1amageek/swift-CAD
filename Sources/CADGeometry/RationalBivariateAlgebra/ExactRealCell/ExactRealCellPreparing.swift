#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public protocol ExactRealCellPreparing: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    init<A: ExactScalarAdmission & ~Copyable>(field: ExactAlgebraicScalarDomain<Base>, variableCount: Int,
        using admission: inout A) throws(ExactRealCellFailure)
    init<A: ExactScalarAdmission & ~Copyable>(retaining source: borrowing ExactRealCellSource<Base>,
        using admission: inout A) throws(ExactRealCellFailure)
    var polynomials: ExactPolynomialDomain<ExactAlgebraicScalarDomain<Base>> { get }
    func bind<A: ExactScalarAdmission & ~Copyable>(polynomials: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>],
        domains: [ExactRealRootInterval<ExactAlgebraicScalar<Base>>], using admission: inout A
    ) throws(ExactRealCellFailure) -> ExactRealCellSource<Base>
    func predicate<A: ExactScalarAdmission & ~Copyable>(instructions: [ExactRealCellInstruction],
        for source: borrowing ExactRealCellSource<Base>, using admission: inout A
    ) throws(ExactRealCellFailure) -> ExactRealCellPredicate<Base>
}
