#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealTopologyReduction<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 /// Non-nil only for exact substitution on a retained singleton coordinate domain.
 public let domainRestriction: ExactRealRootInterval<ExactAlgebraicScalarDomain<Base>.Value>?
 public let variable: Int
 public let originalAtoms: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
 public let originalInstructions: [ExactRealCellInstruction]
 public let derivedAtoms: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
 public let derivedInstructions: [ExactRealCellInstruction]
 init(variable: Int, originalAtoms: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>],
  originalInstructions: [ExactRealCellInstruction], derivedAtoms: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>],
  derivedInstructions: [ExactRealCellInstruction],
  domainRestriction: ExactRealRootInterval<ExactAlgebraicScalarDomain<Base>.Value>? = nil) {
  self.variable = variable; self.originalAtoms = originalAtoms; self.originalInstructions = originalInstructions
  self.derivedAtoms = derivedAtoms; self.derivedInstructions = derivedInstructions; self.domainRestriction = domainRestriction
 }
}
