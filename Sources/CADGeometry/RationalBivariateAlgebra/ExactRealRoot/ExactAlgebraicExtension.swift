#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactAlgebraicExtension<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let domain: ExactAlgebraicScalarDomain<Base>
    public let generator: ExactAlgebraicScalar<Base>
    public let embedding: ExactAlgebraicEmbedding<Base>
}
