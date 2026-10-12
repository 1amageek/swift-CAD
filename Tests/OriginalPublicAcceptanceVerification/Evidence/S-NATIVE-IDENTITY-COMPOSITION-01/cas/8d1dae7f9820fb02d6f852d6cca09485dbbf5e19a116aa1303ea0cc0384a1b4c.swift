#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactAlgebraicEmbedding<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let parent: ExactAlgebraicScalarDomain<Base>
    public let child: ExactAlgebraicScalarDomain<Base>
    public func importing<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing ExactAlgebraicScalar<Base>,
        using admission: inout A) throws(ExactScalarFailure) -> ExactAlgebraicScalar<Base> {
        guard value.context === parent.context else { throw .incompatibleDomain }
        return try child.importing(value, using: &admission)
    }
}
