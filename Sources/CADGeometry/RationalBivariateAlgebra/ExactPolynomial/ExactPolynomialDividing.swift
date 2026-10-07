#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialDividing: Sendable {
    associatedtype Polynomial: Sendable
    associatedtype Division: Sendable
    func divided<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        by divisor: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Division
    func dividedExactly<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        by divisor: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
}
