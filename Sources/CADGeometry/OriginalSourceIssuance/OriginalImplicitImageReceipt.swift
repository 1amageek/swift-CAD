#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// On the selected support, membership is equation == 0 and every guard != 0.
/// This capability intentionally supplies no source parameter correspondence.
public struct OriginalImplicitImageReceipt<Source: Sendable, Selection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let chart: OriginalSourceChart<Source, Selection>
    public let field: Field
    public let polynomials: ExactPolynomialDomain<Field>
    public let equation: ExactPolynomial<Field>
    public let nonzeroGuards: [ExactPolynomial<Field>]
    public var source: OriginalSourceBinding<Source> { chart.binding }
    init(chart: OriginalSourceChart<Source, Selection>, field: Field,
        polynomials: ExactPolynomialDomain<Field>, equation: ExactPolynomial<Field>,
        nonzeroGuards: [ExactPolynomial<Field>]) {
        self.chart = chart; self.field = field; self.polynomials = polynomials
        self.equation = equation; self.nonzeroGuards = nonzeroGuards
    }
}
