#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// A retained element of Q(tan(originalRadians / 2)).
public struct OriginalPhysicalAngleValue: Sendable {
    let owner: OriginalPhysicalAngleOwner
    let numerator: ExactPolynomial<ExactRationalScalarDomain>
    let denominator: ExactPolynomial<ExactRationalScalarDomain>
    public var originalRadians: Double { owner.originalRadians }
    public var depth: ExactScalarDepth {
        get throws(ExactScalarFailure) {
            try .init(value: max(numerator.depth.value, denominator.depth.value),
                coefficient: max(numerator.depth.coefficient, denominator.depth.coefficient))
        }
    }
    init(owner: OriginalPhysicalAngleOwner, numerator: ExactPolynomial<ExactRationalScalarDomain>,
        denominator: ExactPolynomial<ExactRationalScalarDomain>) {
        self.owner = owner; self.numerator = numerator; self.denominator = denominator
    }
}
