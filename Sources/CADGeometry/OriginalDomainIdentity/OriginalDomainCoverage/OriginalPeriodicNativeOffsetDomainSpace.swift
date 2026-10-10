#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct OriginalPeriodicNativeOffsetDomainSpace<S: OriginalOffsetSourceReading>: Sendable where S.Child: OriginalBSplineSourceReading {
    public let family: OriginalPeriodicNativeOffsetLawFamily<S>
    public let child: OriginalBSplineDomainSpace<S.Child,OriginalExactScalarDomain>
    public let frame: OriginalParameterFrame<S,OriginalExactScalarDomain>
    /// Native DI template ordinal to source-law ordinal; the laws remain shared.
    let lawOrdinals: [Int]
    init(family: OriginalPeriodicNativeOffsetLawFamily<S>,child: OriginalBSplineDomainSpace<S.Child,OriginalExactScalarDomain>,
        frame: OriginalParameterFrame<S,OriginalExactScalarDomain>,lawOrdinals: [Int]) {
        self.family=family;self.child=child;self.frame=frame;self.lawOrdinals=lawOrdinals
    }
}
