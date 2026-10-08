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
    public let proofDepth: ExactScalarDepth?
    public var source: OriginalSourceBinding<Source> { chart.binding }
    public var denominator: ExactPolynomial<Field> { homogeneous[3] }

    /// Reusing a law also reuses decisions that are not stored in its coefficients.
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) {
        if let proofDepth { try admission.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient) }
    }

    // Only proved family constructors may issue this source/law binding.
    init(chart: OriginalSourceChart<Source, Selection>, field: Field,
        polynomials: ExactPolynomialDomain<Field>, homogeneous: [ExactPolynomial<Field>],
        support: [OriginalSourceParameterInterval<Field.Value>],
        parameterTransport: OriginalRationalParameterTransport<Field>, proofDepth: ExactScalarDepth? = nil) {
        self.chart = chart; self.field = field; self.polynomials = polynomials
        self.homogeneous = homogeneous; self.support = support
        self.parameterTransport = parameterTransport; self.proofDepth = proofDepth
    }
}
