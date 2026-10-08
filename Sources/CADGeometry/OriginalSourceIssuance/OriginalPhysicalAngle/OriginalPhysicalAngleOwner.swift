#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// All stored state is immutable and shared with retained values.
final class OriginalPhysicalAngleOwner: Sendable {
    let originalRadians: Double
    let rationals: ExactRationalScalarDomain
    let ring: ExactPolynomialDomain<ExactRationalScalarDomain>
    let reducedArgument: ExactRationalCoefficient
    let doublings: Int
    let negative: Bool
    let one: ExactPolynomial<ExactRationalScalarDomain>
    let generator: ExactPolynomial<ExactRationalScalarDomain>
    init(originalRadians: Double, rationals: ExactRationalScalarDomain,
        ring: ExactPolynomialDomain<ExactRationalScalarDomain>, reducedArgument: ExactRationalCoefficient,
        doublings: Int, negative: Bool, one: ExactPolynomial<ExactRationalScalarDomain>,
        generator: ExactPolynomial<ExactRationalScalarDomain>) {
        self.originalRadians = originalRadians; self.rationals = rationals; self.ring = ring
        self.reducedArgument = reducedArgument; self.doublings = doublings; self.negative = negative
        self.one = one; self.generator = generator
    }
}
