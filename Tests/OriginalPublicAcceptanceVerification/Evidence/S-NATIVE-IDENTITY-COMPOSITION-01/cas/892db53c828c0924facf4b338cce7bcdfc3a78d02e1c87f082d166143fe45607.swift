#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact original Rodrigues law with retained child correspondence and position guard.
public struct OriginalRevolutionLawReceipt<S: OriginalRevolutionSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where F.Source == F.Value {
    public let source: OriginalSourceBinding<S>
    public let generator: OriginalRationalChartReceipt<S.Generator,C,F>
    public let field: F
    public let polynomials: ExactPolynomialDomain<F>
    public let homogeneous: [ExactPolynomial<F>]
    public let functions: [OriginalSourceCoordinateFunction<F.Value>]
    public let support: [OriginalSourceParameterInterval<F.Value>]
    public let period: OriginalSourcePeriodReceipt<S,F>
    /// Ring in authored (U,V); maps to the retained generator chart's local parameter.
    public let generatorChartParameter: OriginalRationalParameterTransport<F>
    public let parameterPolynomials: ExactPolynomialDomain<F>
    public let normalizedAxis: [F.Value]
    /// Zero means an original collapsed angular fiber, not a deleted parameter.
    public let radialSquaredNumerator: ExactPolynomial<F>
    public let proofDepth: ExactScalarDepth
    public var denominator: ExactPolynomial<F> { homogeneous[3] }
    init(source: OriginalSourceBinding<S>,generator: OriginalRationalChartReceipt<S.Generator,C,F>,field:F,
        polynomials:ExactPolynomialDomain<F>,homogeneous:[ExactPolynomial<F>],support:[OriginalSourceParameterInterval<F.Value>],
        period:OriginalSourcePeriodReceipt<S,F>,generatorChartParameter:OriginalRationalParameterTransport<F>,
        parameterPolynomials:ExactPolynomialDomain<F>,normalizedAxis:[F.Value],radialSquaredNumerator:ExactPolynomial<F>,proofDepth:ExactScalarDepth) {
        self.source=source; self.generator=generator; self.field=field; self.polynomials=polynomials
        self.homogeneous=homogeneous; self.support=support; self.period=period
        functions=[.intrinsicCosine(axis:0),.intrinsicSine(axis:0),.authoredCoordinate(axis:1)]
        self.generatorChartParameter=generatorChartParameter; self.parameterPolynomials=parameterPolynomials
        self.normalizedAxis=normalizedAxis; self.radialSquaredNumerator=radialSquaredNumerator; self.proofDepth=proofDepth
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            try generator.admitProof(using:&a)
            for value in normalizedAxis { try a.consumeWork(1); _ = try field.sign(of:value,using:&a) }
            for law in homogeneous { _ = try polynomials.degree(of:law,in:2,using:&a) }
            _ = try polynomials.degree(of:radialSquaredNumerator,in:2,using:&a)
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
