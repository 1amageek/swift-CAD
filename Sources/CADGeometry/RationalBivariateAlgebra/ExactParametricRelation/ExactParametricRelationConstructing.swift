#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

public protocol ExactParametricRelationConstructing<Base>: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func map<A: ExactScalarAdmission & ~Copyable>(from source: borrowing ExactRealCellSource<Base>,
        using admission: inout A) throws(ExactParametricRelationFailure) -> ExactParametricMap<Base>
    func compile<A: ExactScalarAdmission & ~Copyable>(kind: ExactParametricRelationKind,
        first: borrowing ExactParametricMap<Base>, second: borrowing ExactParametricMap<Base>,
        using admission: inout A) throws(ExactParametricRelationFailure) -> ExactParametricRelationSource<Base>
}
