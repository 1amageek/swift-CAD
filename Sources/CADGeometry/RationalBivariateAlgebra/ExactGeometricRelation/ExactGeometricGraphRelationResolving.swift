#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public protocol ExactGeometricGraphRelationResolving: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func resolve<A: ExactScalarAdmission & ~Copyable>(_ relation: borrowing ExactParametricGraphRelation<Base>,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricGraphRelation<Base>
    func point<A: ExactScalarAdmission & ~Copyable>(atParameterOrdinal ordinal: Int,
        in relation: borrowing ExactGeometricGraphRelation<Base>, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricGraphPoint<Base>
    func fiber<A: ExactScalarAdmission & ~Copyable>(at station: borrowing ExactGeometricStation<Base>,
        in relation: borrowing ExactGeometricGraphRelation<Base>, limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricGraphFiber<Base>
    func containsLift<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>,
        in fiber: borrowing ExactGeometricGraphFiber<Base>, limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> Bool
    func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactXYZ<Base>,
        in relation: borrowing ExactGeometricGraphRelation<Base>, limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> Bool
}
