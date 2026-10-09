#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed local position graph retaining the actual source theorem and all auxiliary witnesses.
public struct OriginalParametricGraphReceipt<S:Sendable,F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,E:Sendable>:Sendable {
    public let source:OriginalSourceBinding<S>
    public let evidence:E
    public let field:F
    public let polynomials:ExactPolynomialDomain<F>
    public let homogeneous:[ExactPolynomial<F>]
    public let support:[OriginalSourceParameterInterval<F.Value>]
    public let includesUpperBoundary:[Bool]
    public let layout:OriginalParametricVariableLayout
    public let conditions:[OriginalParametricGraphCondition<F>]
    public let parameterTransport:OriginalRationalParameterTransport<F>
    public let proofDepth:ExactScalarDepth
    init(source:OriginalSourceBinding<S>,evidence:E,field:F,polynomials:ExactPolynomialDomain<F>,
        homogeneous:[ExactPolynomial<F>],support:[OriginalSourceParameterInterval<F.Value>],includesUpperBoundary:[Bool],
        layout:OriginalParametricVariableLayout,conditions:[OriginalParametricGraphCondition<F>],
        parameterTransport:OriginalRationalParameterTransport<F>,proofDepth:ExactScalarDepth) {
        self.source=source;self.evidence=evidence;self.field=field;self.polynomials=polynomials
        self.homogeneous=homogeneous;self.support=support;self.includesUpperBoundary=includesUpperBoundary
        self.layout=layout;self.conditions=conditions;self.parameterTransport=parameterTransport;self.proofDepth=proofDepth
    }
    public func admits<A:ExactScalarAdmission & ~Copyable>(_ coordinates:borrowing [F.Value],
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure)->Bool {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            guard coordinates.count==layout.variableCount else { throw OriginalSourceIssuanceFailure.invalidChart }
            var accepted=true
            for axis in layout.parameters.indices {
                try a.consumeWork(1)
                let value=coordinates[layout.parameters[axis]]
                let lower=try field.compare(value,support[axis].lower,using:&a)
                let upper=try field.compare(value,support[axis].upper,using:&a)
                if lower == .less || upper == .greater || (upper == .equal && !includesUpperBoundary[axis]) { accepted=false }
            }
            for condition in conditions {
                try a.consumeWork(1)
                let value=try polynomials.evaluated(condition.polynomial,at:copy coordinates,using:&a).value
                if try !condition.accepts(field.sign(of:value,using:&a)) { accepted=false }
            }
            try a.checkpoint();return accepted
        } catch { throw .init(preserving:error) }
    }
}
