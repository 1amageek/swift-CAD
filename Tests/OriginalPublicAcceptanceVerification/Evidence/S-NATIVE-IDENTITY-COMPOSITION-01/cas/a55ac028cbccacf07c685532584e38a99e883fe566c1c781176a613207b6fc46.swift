#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Enclosing chart selection plus the retained mandatory original source guard.
public struct OriginalNativeOffsetChartOccurrence<S: OriginalOffsetSourceReading>: Sendable where S.Child: OriginalBSplineSourceReading {
    public let family: OriginalFiniteNativeOffsetLawFamily<S>
    public let template: Int
    public let enclosingSelection: OriginalParameterSelection<S,OriginalExactScalarDomain>
    public var law: OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain> { family.laws[template] }
    init(family: OriginalFiniteNativeOffsetLawFamily<S>,template: Int,
        enclosingSelection: OriginalParameterSelection<S,OriginalExactScalarDomain>) {
        self.family = family;self.template = template;self.enclosingSelection = enclosingSelection
    }
}
