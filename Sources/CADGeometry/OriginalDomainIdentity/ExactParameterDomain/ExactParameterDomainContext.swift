#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

/// Immutable parameter-axis authority, shared by every set issued by one domain.
final class ExactParameterDomainContext<F: ExactScalarOrdering>: Sendable {
    let field: F
    let depth: ExactScalarDepth
    init(field: F, depth: ExactScalarDepth) { self.field = field; self.depth = depth }
}
