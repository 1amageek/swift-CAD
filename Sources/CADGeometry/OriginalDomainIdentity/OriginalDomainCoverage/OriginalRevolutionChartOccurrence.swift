#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Retains the whole generator witness and the selected original chart side.
public struct OriginalRevolutionChartOccurrence<S: OriginalRevolutionSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where F.Source == F.Value {
    public let family: OriginalFiniteRevolutionLawFamily<S,C,F>
    public let template: Int
    public let transport: OriginalParameterTransport<S,F>
    public var law: OriginalRevolutionLawReceipt<S,C,F> { family.laws[template] }
    init(family: OriginalFiniteRevolutionLawFamily<S,C,F>,template: Int,transport: OriginalParameterTransport<S,F>) {
        self.family = family;self.template = template;self.transport = transport
    }
}
