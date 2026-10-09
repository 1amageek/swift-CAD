#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Constraint syntax alone is not a proof. Retain the issuer-produced relation view.
public enum OriginalParameterIdentityConstraints<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    /// right[i] = gains[i] * left[permutation[i]] + offsets[i], within both scopes.
    case affine(permutation: [Int], gains: [F.Value], offsets: [F.Value])
    /// Every pair in the retained left/right scopes is certified by the original proof.
    case completeProduct
}
