#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

public protocol ExactParametricRelationResolving<Base>: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func resolve<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactParametricRelationSource<Base>,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits,
        using admission: inout A) throws(ExactParametricRelationFailure) -> ExactParametricRelation<Base>
    func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>,
        in relation: borrowing ExactParametricRelation<Base>, rootLimits: ExactRealRootLimits,
        using admission: inout A) throws(ExactParametricRelationFailure) -> Bool
}
