#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// A retained exact rational function of mathematical pi.
public struct OriginalPiValue: Sendable {
    let owner: OriginalPiOwner
    let numerator: ExactPolynomial<ExactRationalScalarDomain>
    let denominator: ExactPolynomial<ExactRationalScalarDomain>
    public var depth: ExactScalarDepth {
        get throws(ExactScalarFailure) {
            try .init(value: max(numerator.depth.value, denominator.depth.value),
                coefficient: max(numerator.depth.coefficient, denominator.depth.coefficient))
        }
    }
    init(owner: OriginalPiOwner, numerator: ExactPolynomial<ExactRationalScalarDomain>,
        denominator: ExactPolynomial<ExactRationalScalarDomain>) {
        self.owner = owner; self.numerator = numerator; self.denominator = denominator
    }
}
