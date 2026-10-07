#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public protocol ExactRealIncidenceProducing<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func incidence<A: ExactScalarAdmission & ~Copyable>(of selection: borrowing ExactRealCellSelection<Base>, strategy: ExactRealClosureStrategy,
  limits: ExactRealTopologyLimits, using admission: inout A) throws(ExactRealTopologyFailure) -> ExactRealIncidence<Base>
}
