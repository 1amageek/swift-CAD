#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol ExactRealRootPreparing: Sendable {
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    var polynomials: ExactPolynomialDomain<Field> { get }
    func bind<A: ExactScalarAdmission & ~Copyable>(_ polynomial: borrowing ExactPolynomial<Field>,
        variable: Int, refinementAxis: ExactScalarRootAxis, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSource<Field>
    func domain<A: ExactScalarAdmission & ~Copyable>(lower: ExactRealRootBound<Field.Value>,
        upper: ExactRealRootBound<Field.Value>, includesLower: Bool, includesUpper: Bool,
        using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRootInterval<Field.Value>
    func emptyDomain<A: ExactScalarAdmission & ~Copyable>(using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootInterval<Field.Value>
}
