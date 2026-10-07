#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealTopologyRegion<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 public let partition: ExactRealCellPartition<Base>
 public let coordinateCount: Int
 public let cells: [ExactRealCellID<Base>]
 public let included: [Bool]
 public let excludesExterior: Bool
 public let formulaAtoms: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
 public let signInvariants: [ExactRealTopologySignInvariant<Base>]
 public let certifiedTarget: ExactRealCellID<Base>?
 public let reductions: [ExactRealTopologyReduction<Base>]
 public let eliminations: [ExactRealTopologyElimination<Base>]
 public let depth: ExactScalarDepth
 // All node decisions and quantifier scopes retain coverage, including exclusions.
 let decisions: [ExactTopologyDecision<Base>]
 let quantifiers: [Bool]
 let instructions: [ExactRealCellInstruction]
}
