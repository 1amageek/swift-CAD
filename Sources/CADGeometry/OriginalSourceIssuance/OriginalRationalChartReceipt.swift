#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Immutable source, local law and correspondence. This is not a solution receipt.
public struct OriginalRationalChartReceipt<Source: Sendable, Selection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let chart: OriginalSourceChart<Source, Selection>
    public let field: Field
    public let polynomials: ExactPolynomialDomain<Field>
    public let homogeneous: [ExactPolynomial<Field>]
    public let support: [OriginalSourceParameterInterval<Field.Value>]
    public let parameterTransport: OriginalRationalParameterTransport<Field>
    public var source: OriginalSourceBinding<Source> { chart.binding }
    public var denominator: ExactPolynomial<Field> { homogeneous[3] }

    // Only proved family constructors may issue this source/law binding.
    init(chart: OriginalSourceChart<Source, Selection>, field: Field,
        polynomials: ExactPolynomialDomain<Field>, homogeneous: [ExactPolynomial<Field>],
        support: [OriginalSourceParameterInterval<Field.Value>],
        parameterTransport: OriginalRationalParameterTransport<Field>) {
        self.chart = chart; self.field = field; self.polynomials = polynomials
        self.homogeneous = homogeneous; self.support = support
        self.parameterTransport = parameterTransport
    }
}
