#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public protocol ExactRealComponentsProducing<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func components<A: ExactScalarAdmission & ~Copyable>(of incidence: borrowing ExactRealIncidence<Base>, limits: ExactRealTopologyLimits,
  using admission: inout A) throws(ExactRealTopologyFailure) -> ExactRealComponents<Base>
}
