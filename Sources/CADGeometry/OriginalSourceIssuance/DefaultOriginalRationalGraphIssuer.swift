#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Uses an already issued rational source law; it never refits the original map.
public struct DefaultOriginalRationalGraphIssuer<S:Sendable,C:Sendable,F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:OriginalParametricGraphIssuing where F.Source == F.Value {
    public typealias Source=S
    public typealias Field=F
    public typealias Evidence=OriginalRationalChartReceipt<S,C,F>
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(_ evidence:borrowing Evidence,limits:OriginalSourceIssuanceLimits,
        using admission:inout A)
        throws(OriginalSourceIssuanceFailure)->OriginalParametricGraphReceipt<S,F,Evidence> {
        let law=copy evidence
        do {
            return try admission.withProofScope { a in
                try law.source.require(limits);try law.admitProof(using:&a)
                let n=law.polynomials.variableCount
                guard n==law.support.count,law.homogeneous.count==4,
                    law.parameterTransport.numerators.count==n,law.parameterTransport.denominators.count==n else { throw OriginalSourceIssuanceFailure.invalidChart }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Int.self))
                let layout=try OriginalParametricVariableLayout.checked(variableCount:n,parameters:Array(0..<n),auxiliaries:[],using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Bool.self))
                let sides=[Bool](repeating:true,count:n)
                let count=n.addingReportingOverflow(1)
                guard !count.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:OriginalParametricGraphCondition<F>.self))
                var guards:[OriginalParametricGraphCondition<F>]=[];guards.reserveCapacity(count.partialValue)
                guards.append(.init(try law.polynomials.importing(law.denominator,using:&a),.notEqual))
                for d in law.parameterTransport.denominators {
                    try a.consumeWork(1);guards.append(.init(try law.polynomials.importing(d,using:&a),.notEqual))
                }
                for p in law.homogeneous { _=try law.polynomials.importing(p,using:&a) }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalParametricGraphReceipt<S,F,Evidence>.self))
                let result=OriginalParametricGraphReceipt(source:law.source,evidence:law,field:law.field,polynomials:law.polynomials,
                    homogeneous:law.homogeneous,support:law.support,includesUpperBoundary:sides,layout:layout,
                    conditions:guards,parameterTransport:law.parameterTransport,proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}
