#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// One authored-T frame and one retained all-integer auxiliary surface cover.
public struct OriginalPeriodicNativeSurfaceLiftDomainSpace<S: OriginalLiftSourceReading>: Sendable {
    public let family: OriginalPeriodicNativeSurfaceLiftGraphs<S>
    public let frame: OriginalParameterFrame<S,OriginalExactScalarDomain>
    public let surface: OriginalBSplineDomainCover<S.Surface,OriginalExactScalarDomain>
    let lawOrdinals: [Int]
    init(family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,frame: OriginalParameterFrame<S,OriginalExactScalarDomain>,
        surface: OriginalBSplineDomainCover<S.Surface,OriginalExactScalarDomain>,lawOrdinals: [Int]) {
        self.family=family;self.frame=frame;self.surface=surface;self.lawOrdinals=lawOrdinals
    }
}
