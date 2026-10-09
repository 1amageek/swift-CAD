#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Nonforgeable read-only relation retaining the original identity proof and scopes.
public struct OriginalParameterIdentityRelation<Source: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let receipt: OriginalParameterIdentity<Source,F>
    public var left: OriginalParameterSelection<Source,F> { receipt.left }
    public var right: OriginalParameterSelection<Source,F> { receipt.right }
    public var kind: OriginalParameterIdentityKind { receipt.kind }
    public var depth: Int { receipt.depth }
    public var evidenceDepth: ExactScalarDepth { receipt.evidenceDepth }
    public var evidenceSourceDepth: Int { receipt.evidenceSourceDepth }
    public var proofCount: Int { receipt.proofCount }
    public var constraints: OriginalParameterIdentityConstraints<F> {
        if let permutation = receipt.permutation {
            return .affine(permutation:permutation,gains:receipt.gains,offsets:receipt.offsets)
        }
        return .completeProduct
    }
    init(receipt: OriginalParameterIdentity<Source,F>) { self.receipt = receipt }
}
