#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public protocol ExactGeometricRelationQuerying<Base>: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactXYZ<Base>,
        in relation: borrowing ExactGeometricRelation<Base>, limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> Bool
    func fiber<A: ExactScalarAdmission & ~Copyable>(at station: borrowing ExactGeometricStation<Base>,
        in relation: borrowing ExactGeometricRelation<Base>, limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricFiber<Base>
}
