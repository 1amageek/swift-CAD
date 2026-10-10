#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Refines new consumer guards over a complete retained L5 parameter selection.
public protocol NativeExactParameterRefining: Sendable {
    func refine<A: ExactScalarAdmission & ~Copyable>(
        _ raw: borrowing ExactParametricRelation<ExactRationalScalarDomain>,
        matching predicate: borrowing ExactRealCellPredicate<ExactRationalScalarDomain>,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,
        using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParameterRefinement
}
