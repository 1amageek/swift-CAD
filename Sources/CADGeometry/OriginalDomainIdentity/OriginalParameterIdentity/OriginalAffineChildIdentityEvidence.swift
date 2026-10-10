#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Shares the complete source cover and original proof without copying their arrays.
final class OriginalAffineChildIdentityEvidence<S: Sendable,C: OriginalChartFamilyQuerying>: Sendable {
    let cover: OriginalAffineChildDomainCover<S,C>
    let child: OriginalParameterIdentity<C.Source,C.Field>
    init(cover: OriginalAffineChildDomainCover<S,C>, child: OriginalParameterIdentity<C.Source,C.Field>) {
        self.cover = cover; self.child = child
    }
}
