#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Immutable polynomial ownership. Query-local refinement never mutates it.
final class OriginalPiOwner: Sendable {
    let rationals: ExactRationalScalarDomain
    let ring: ExactPolynomialDomain<ExactRationalScalarDomain>
    let one: ExactPolynomial<ExactRationalScalarDomain>
    let generator: ExactPolynomial<ExactRationalScalarDomain>
    init(rationals: ExactRationalScalarDomain,ring: ExactPolynomialDomain<ExactRationalScalarDomain>,
        one: ExactPolynomial<ExactRationalScalarDomain>,generator: ExactPolynomial<ExactRationalScalarDomain>) {
        self.rationals = rationals; self.ring = ring; self.one = one; self.generator = generator
    }
}
