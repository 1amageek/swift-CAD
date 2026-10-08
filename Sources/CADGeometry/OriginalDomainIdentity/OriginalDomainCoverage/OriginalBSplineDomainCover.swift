#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// A finite cover or an all-integer family, with every original request retained.
public struct OriginalBSplineDomainCover<S: OriginalBSplineSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let space: OriginalBSplineDomainSpace<S,F>
    public let request: OriginalParameterSelection<S,F>
    public let effective: OriginalParameterSelection<S,F>
    /// Nonperiodic covers are finite; periodic families remain symbolic, even for finite requests.
    public let finite: OriginalDomainCover<S,F>?
    public var integerFamilyRank: Int { space.periods.count }
    init(space: OriginalBSplineDomainSpace<S,F>,request: OriginalParameterSelection<S,F>,
        effective: OriginalParameterSelection<S,F>,finite: OriginalDomainCover<S,F>?) {
        self.space = space; self.request = request; self.effective = effective; self.finite = finite
    }
}
