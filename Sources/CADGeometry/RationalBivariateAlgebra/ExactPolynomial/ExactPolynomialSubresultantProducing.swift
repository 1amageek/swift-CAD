#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialSubresultantProducing: Sendable {
    associatedtype Polynomial: Sendable
    associatedtype Subresultants: Sendable
    func principalSubresultants<A: ExactScalarAdmission & ~Copyable>(
        _ first: borrowing Polynomial, _ second: borrowing Polynomial, eliminating variable: Int,
        using admission: inout A) throws(ExactPolynomialFailure) -> Subresultants
}
