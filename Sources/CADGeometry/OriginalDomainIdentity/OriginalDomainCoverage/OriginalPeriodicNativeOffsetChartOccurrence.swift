#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Original lifted UV enclosure plus the unreduced child owner and normal guard.
public struct OriginalPeriodicNativeOffsetChartOccurrence<S: OriginalOffsetSourceReading>: Sendable where S.Child: OriginalBSplineSourceReading {
    public let family: OriginalPeriodicNativeOffsetLawFamily<S>
    public let template: Int
    public let lawOrdinal: Int
    public let child: OriginalBSplineChartOccurrence<S.Child,OriginalExactScalarDomain>
    public let enclosingSelection: OriginalParameterSelection<S,OriginalExactScalarDomain>
    public var cycles: [OriginalParameterCycle] { child.cycles }
    public var law: OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain> { family.laws[lawOrdinal] }
    init(family: OriginalPeriodicNativeOffsetLawFamily<S>,template: Int,lawOrdinal: Int,
        child: OriginalBSplineChartOccurrence<S.Child,OriginalExactScalarDomain>,
        enclosingSelection: OriginalParameterSelection<S,OriginalExactScalarDomain>) {
        self.family=family;self.template=template;self.lawOrdinal=lawOrdinal;self.child=child;self.enclosingSelection=enclosingSelection
    }
}
