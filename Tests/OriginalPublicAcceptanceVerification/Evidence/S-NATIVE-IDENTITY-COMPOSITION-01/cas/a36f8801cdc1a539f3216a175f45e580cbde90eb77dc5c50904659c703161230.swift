#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialConstructing: Sendable {
    associatedtype Coefficient: Sendable
    associatedtype Polynomial: Sendable
    func zero<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
    func constant<A: ExactScalarAdmission & ~Copyable>(_ coefficient: borrowing Coefficient, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
    func variable<A: ExactScalarAdmission & ~Copyable>(_ index: Int, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
    func polynomial<A: ExactScalarAdmission & ~Copyable>(terms: [ExactPolynomialTerm<Coefficient>], using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
}
