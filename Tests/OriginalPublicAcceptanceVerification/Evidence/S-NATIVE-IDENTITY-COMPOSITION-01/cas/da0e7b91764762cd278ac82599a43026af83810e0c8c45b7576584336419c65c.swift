#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// One original closed curve cell side with exact selected authored T correspondence.
public struct OriginalRetainedCurveChartOccurrence<S: OriginalRetainedCurveSourceReading>: Sendable {
    public let family: OriginalFiniteRetainedCurveCharts<S>
    public let template: Int
    public let transport: OriginalParameterTransport<S,S.Field>
    public var law: OriginalRationalChartReceipt<S,Int,S.Field> { family.laws[template] }
    public var localSelection: OriginalParameterSelection<S,S.Field> { transport.local }
    public var selectedImage: OriginalParameterSelection<S,S.Field> { transport.image }
    init(family: OriginalFiniteRetainedCurveCharts<S>,template: Int,transport: OriginalParameterTransport<S,S.Field>) {
        self.family=family;self.template=template;self.transport=transport
    }
}
