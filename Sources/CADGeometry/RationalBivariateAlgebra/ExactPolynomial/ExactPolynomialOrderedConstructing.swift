#if L1_ISOLATED_VERIFICATION
import L0
#endif

/// Validates canonical order and retains input backing without normalization.
public protocol ExactPolynomialOrderedConstructing: ExactPolynomialConstructing {
    func polynomial<A: ExactScalarAdmission & ~Copyable>(
        orderedTerms: [ExactPolynomialTerm<Coefficient>], using admission: inout A
    ) throws(ExactPolynomialFailure) -> Polynomial
}
