#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialDeciding: Sendable {
    associatedtype Polynomial: Sendable
    func isZero<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Bool
    func equals<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Bool
    func degree<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Polynomial, in variable: Int, using admission: inout A) throws(ExactPolynomialFailure) -> Int?
}
