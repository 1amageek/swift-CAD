#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialImporting: Sendable {
    associatedtype Polynomial: Sendable
    func importing<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
}

extension ExactPolynomialDomain: ExactPolynomialImporting where F: ExactScalarImporting, F.Source == F.Value {}
