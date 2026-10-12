#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealTopologyElimination<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let variable: Int
 public let equality: Int
 public let originalAtoms: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
 public let originalInstructions: [ExactRealCellInstruction]
 public let replacement: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let variableMap: [Int]
}
