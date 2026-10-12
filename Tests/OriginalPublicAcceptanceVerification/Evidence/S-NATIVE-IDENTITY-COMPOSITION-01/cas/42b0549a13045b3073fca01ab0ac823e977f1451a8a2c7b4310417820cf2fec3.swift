#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Intersect the child occurrence with correspondence.local before consumption.
/// The correspondence is the request scope, not the individual chart support.
public struct OriginalAffineChildDomainOccurrence<Source: Sendable, Child: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let child: Child
    public let correspondence: OriginalParameterTransport<Source, Field>
    init(child: Child, correspondence: OriginalParameterTransport<Source, Field>) {
        self.child = child; self.correspondence = correspondence
    }
}
