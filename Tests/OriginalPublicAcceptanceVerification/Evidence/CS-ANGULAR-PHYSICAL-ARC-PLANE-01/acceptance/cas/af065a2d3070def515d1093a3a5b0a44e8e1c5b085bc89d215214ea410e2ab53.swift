#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Every original law's guarded axis section, complete only for the retained axis-line pair.
public struct OriginalRevolutionAxisSectionReceipt<S: OriginalRevolutionSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,L: OriginalLinearSourceReading>: Sendable where F.Source == F.Value {
    public let family: OriginalFiniteRevolutionLawFamily<S,C,F>
    public let line: OriginalSourceBinding<L>
    public let graphs: [OriginalParametricGraphReceipt<S,F,OriginalRevolutionAxisSectionEvidence<S,C,F,L>>]
    public let proofDepth: ExactScalarDepth
    init(family: OriginalFiniteRevolutionLawFamily<S,C,F>,line: OriginalSourceBinding<L>,
        graphs: [OriginalParametricGraphReceipt<S,F,OriginalRevolutionAxisSectionEvidence<S,C,F,L>>],proofDepth: ExactScalarDepth) {
        self.family=family;self.line=line;self.graphs=graphs;self.proofDepth=proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using admission: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try admission.checkpoint();try family.admitProof(limits:limits,using:&admission);try line.require(limits)
            try admission.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for graph in graphs {
                try admission.consumeWork(1);try graph.evidence.admitProof(limits:limits,using:&admission)
                try admission.admitDepth(value:graph.proofDepth.value,coefficient:graph.proofDepth.coefficient)
                for interval in graph.support { _ = try graph.field.compare(interval.lower,interval.upper,using:&admission) }
                for polynomial in graph.homogeneous { _ = try graph.polynomials.degree(of:polynomial,in:1,using:&admission) }
                for condition in graph.conditions { _ = try graph.polynomials.degree(of:condition.polynomial,in:1,using:&admission) }
                for polynomial in graph.parameterTransport.numerators { _ = try graph.polynomials.degree(of:polynomial,in:1,using:&admission) }
                for polynomial in graph.parameterTransport.denominators { _ = try graph.polynomials.degree(of:polynomial,in:1,using:&admission) }
            }
            try admission.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
