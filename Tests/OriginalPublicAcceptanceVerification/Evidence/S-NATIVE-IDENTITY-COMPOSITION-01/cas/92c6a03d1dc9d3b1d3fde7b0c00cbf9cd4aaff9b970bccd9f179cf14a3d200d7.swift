#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialArithmetic: Sendable {
    associatedtype Polynomial: Sendable
    associatedtype Coefficient: Sendable
    func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
    func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
    func scaled<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, by coefficient: borrowing Coefficient, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
}
