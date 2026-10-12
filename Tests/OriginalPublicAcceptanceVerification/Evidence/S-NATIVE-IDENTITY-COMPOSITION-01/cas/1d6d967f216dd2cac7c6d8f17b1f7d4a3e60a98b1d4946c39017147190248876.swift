#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellBoundaryRoot<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
 // The parent handle retains the full coefficient, reductum, PSC and complete-root proof.
 public let parent: ExactRealCellID<Base>
 public let axis: Int
 public let rootOrdinal: Int
 public let incomingLawIndex: Int
 public let incomingLaw: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let incomingMultiplicity: Int
 public let incomingDerivativeSigns: [ExactSign]
 public var parentEvidence: ExactRealCellStackEvidence<Base> {
  .init(parent: parent, stackIndex: parent.owner.records[parent.index].stack)
 }
 public let polynomial: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
 public let derivativeSigns: [ExactSign]
 public let depth: ExactScalarDepth
}
