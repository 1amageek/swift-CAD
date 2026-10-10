#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Shares both parent covers, source actions and the original child proof.
final class OriginalAffinePairedIdentityEvidence<S: Sendable,L: OriginalChartFamilyQuerying,R: OriginalChartFamilyQuerying>: Sendable where L.Source == R.Source, L.Field == R.Field {
    let left: OriginalAffineChildDomainCover<S,L>
    let right: OriginalAffineChildDomainCover<S,R>
    let child: OriginalParameterIdentity<L.Source,L.Field>
    let leftAction: OriginalSourceAffineActionReceipt<S,L.Field>
    let rightAction: OriginalSourceAffineActionReceipt<S,L.Field>
    init(left: OriginalAffineChildDomainCover<S,L>,right: OriginalAffineChildDomainCover<S,R>,
        child: OriginalParameterIdentity<L.Source,L.Field>,leftAction: OriginalSourceAffineActionReceipt<S,L.Field>,rightAction: OriginalSourceAffineActionReceipt<S,L.Field>) {
        self.left = left;self.right = right;self.child = child
        self.leftAction = leftAction;self.rightAction = rightAction
    }
}
