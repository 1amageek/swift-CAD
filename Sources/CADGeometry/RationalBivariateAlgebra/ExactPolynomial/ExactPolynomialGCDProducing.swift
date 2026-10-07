#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialGCDProducing: Sendable {
    associatedtype Polynomial: Sendable
    func greatestCommonDivisor<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing Polynomial,
        _ second: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
}
