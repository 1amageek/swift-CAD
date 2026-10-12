#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original child law retained in local coordinates with exact aggregate station map.
public struct OriginalGuideChartReceipt<S:OriginalGuideSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:Sendable where F.Source == F.Value {
    public let source:OriginalSourceBinding<S>
    public let child:OriginalRationalChartReceipt<S.Traversal,C,F>
    public let traversalIndex:Int
    public let originalSegmentOrdinal:Int
    public let field:F
    public let polynomials:ExactPolynomialDomain<F>
    public let homogeneous:[ExactPolynomial<F>]
    public let localSupport:OriginalSourceParameterInterval<F.Value>
    public let parameterTransport:OriginalRationalParameterTransport<F>
    public let aggregateSupport:OriginalSourceParameterInterval<F.Value>
    public let proofDepth:ExactScalarDepth
    init(source:OriginalSourceBinding<S>,child:OriginalRationalChartReceipt<S.Traversal,C,F>,
        traversalIndex:Int,originalSegmentOrdinal:Int,field:F,polynomials:ExactPolynomialDomain<F>,
        homogeneous:[ExactPolynomial<F>],localSupport:OriginalSourceParameterInterval<F.Value>,
        parameterTransport:OriginalRationalParameterTransport<F>,aggregateSupport:OriginalSourceParameterInterval<F.Value>,proofDepth:ExactScalarDepth) {
        self.source=source;self.child=child;self.traversalIndex=traversalIndex
        self.originalSegmentOrdinal=originalSegmentOrdinal;self.field=field;self.polynomials=polynomials
        self.homogeneous=homogeneous;self.localSupport=localSupport
        self.parameterTransport=parameterTransport;self.aggregateSupport=aggregateSupport;self.proofDepth=proofDepth
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            try child.admitProof(using:&a)
            for p in homogeneous { _ = try polynomials.degree(of:p,in:0,using:&a) }
            for p in parameterTransport.numerators { _ = try polynomials.degree(of:p,in:0,using:&a) }
            for p in parameterTransport.denominators { _ = try polynomials.degree(of:p,in:0,using:&a) }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
