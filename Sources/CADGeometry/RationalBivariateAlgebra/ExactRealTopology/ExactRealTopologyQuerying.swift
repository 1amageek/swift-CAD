#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public protocol ExactRealTopologyQuerying<Base>: Sendable {
 associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
 func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>, in closure: borrowing ExactRealClosure<Base>,
  limits: ExactRealTopologyLimits, using admission: inout A) throws(ExactRealTopologyFailure) -> Bool
}
