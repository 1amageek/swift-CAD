#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialSquareFreeProducing: Sendable {
    associatedtype Polynomial: Sendable
    associatedtype SquareFreeDecomposition: Sendable
    func squareFreeDecomposition<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> SquareFreeDecomposition
}
