#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public typealias ExactRealTopology<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting> = ExactRealTopologyDomain<Base, ExactRealCellDomain<Base>> where Base.Source == Base.Value
