#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealTopologyReduction<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let variable: Int
 public let originalAtoms: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
 public let originalInstructions: [ExactRealCellInstruction]
 public let derivedAtoms: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
 public let derivedInstructions: [ExactRealCellInstruction]
}
