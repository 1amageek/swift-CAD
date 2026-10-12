#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

/// Exact source-cell classification after a coordinate projection and refinement.
public protocol ExactRealCellPullbackResolving<Base>: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func refinePullback<A: ExactScalarAdmission & ~Copyable>(
        of source: borrowing ExactRealCellSelection<Base>,
        onto target: borrowing ExactRealCellPredicate<Base>,
        coordinateMap: borrowing [Int], cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(ExactRealTopologyFailure) -> ExactRealCellPullback<Base>
}
