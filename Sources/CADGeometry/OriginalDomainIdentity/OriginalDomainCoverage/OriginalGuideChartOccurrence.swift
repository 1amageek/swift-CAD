#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// One original closed guide side with exact selected child-local correspondence.
public struct OriginalGuideChartOccurrence<S: OriginalGuideSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where F.Source == F.Value {
    public let family: OriginalFiniteGuideChartFamily<S,C,F>
    public let template: Int
    public let transport: OriginalParameterTransport<S,F>
    public var law: OriginalGuideChartReceipt<S,C,F> { family.laws[template] }
    public var localSelection: OriginalParameterSelection<S,F> { transport.local }
    public var selectedImage: OriginalParameterSelection<S,F> { transport.image }
    init(family: OriginalFiniteGuideChartFamily<S,C,F>,template: Int,transport: OriginalParameterTransport<S,F>) {
        self.family=family;self.template=template;self.transport=transport
    }
}
