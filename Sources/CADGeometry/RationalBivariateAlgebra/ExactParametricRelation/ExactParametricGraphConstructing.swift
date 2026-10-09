#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

public protocol ExactParametricGraphConstructing<Base>: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func graph<A: ExactScalarAdmission & ~Copyable>(from predicate: borrowing ExactRealCellPredicate<Base>,
        parameterCount: Int, using admission: inout A) throws(ExactParametricRelationFailure) -> ExactParametricGraph<Base>
    func compile<A: ExactScalarAdmission & ~Copyable>(kind: ExactParametricRelationKind,
        first: borrowing ExactParametricGraph<Base>, second: borrowing ExactParametricGraph<Base>,
        using admission: inout A) throws(ExactParametricRelationFailure) -> ExactParametricGraphRelationSource<Base>
}
