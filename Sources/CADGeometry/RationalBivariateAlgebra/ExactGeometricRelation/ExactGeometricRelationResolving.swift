#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public protocol ExactGeometricRelationResolving<Base>: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func resolve<A: ExactScalarAdmission & ~Copyable>(_ relation: borrowing ExactParametricRelation<Base>,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricRelation<Base>
}
