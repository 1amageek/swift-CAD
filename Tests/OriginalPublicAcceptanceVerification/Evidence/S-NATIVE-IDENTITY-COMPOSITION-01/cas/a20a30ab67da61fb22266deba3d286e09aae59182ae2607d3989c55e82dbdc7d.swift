#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact original parameters are numerator/denominator, retaining every guard.
public struct OriginalRationalParameterTransport<Field: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let numerators: [ExactPolynomial<Field>]
    public let denominators: [ExactPolynomial<Field>]
    init(numerators: [ExactPolynomial<Field>], denominators: [ExactPolynomial<Field>]) {
        self.numerators = numerators
        self.denominators = denominators
    }
}
