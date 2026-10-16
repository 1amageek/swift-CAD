#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Transfers the existing original positive-normal-length relation without another producer.
public struct DefaultOriginalOffsetGraphIssuer<S:OriginalOffsetSourceReading,C:Sendable,F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:OriginalParametricGraphIssuing where F.Source==F.Value {
    public typealias Source=S
    public typealias Field=F
    public typealias Evidence=OriginalOffsetLawReceipt<S,C,F>
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(_ evidence:borrowing Evidence,limits:OriginalSourceIssuanceLimits,
        using admission:inout A)
        throws(OriginalSourceIssuanceFailure)->OriginalParametricGraphReceipt<S,F,Evidence> {
        let law=copy evidence
        do {
            return try admission.withProofScope { a in
                try law.admitProof(limits:limits,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
                let layout=try OriginalParametricVariableLayout.checked(variableCount:3,parameters:[0,1],auxiliaries:[2],using:&a)
                let ring=law.polynomials
                let size=law.child.parameterTransport.denominators.count.addingReportingOverflow(5)
                guard !size.overflow else { throw OriginalSourceIssuanceFailure.countOverflow };let count=size.partialValue
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:OriginalParametricGraphCondition<F>.self))
                var guards:[OriginalParametricGraphCondition<F>]=[];guards.reserveCapacity(count)
                guards.append(.init(law.positiveRootEquation,.equal))
                guards.append(.init(try ring.variable(2,using:&a),.positive))
                guards.append(.init(law.normalSquared,.positive))
                guards.append(.init(law.denominator,.notEqual))
                for ordinal in 0...law.child.parameterTransport.denominators.count {
                    let polynomial = ordinal == 0 ? law.child.denominator : law.child.parameterTransport.denominators[ordinal-1]
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:polynomial.termCount,of:ExactPolynomialTerm<F.Value>.self))
                    var terms:[ExactPolynomialTerm<F.Value>]=[];terms.reserveCapacity(polynomial.termCount)
                    for term in polynomial.terms {
                        try a.consumeWork(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
                        terms.append(.init(powers:[term.powers[0],term.powers[1],0],coefficient:try law.field.importing(term.coefficient,using:&a)))
                    }
                    guards.append(.init(try ring.polynomial(terms:terms,using:&a),.notEqual))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalParametricGraphReceipt<S,F,Evidence>.self))
                let result=OriginalParametricGraphReceipt(source:law.source,evidence:law,field:law.field,polynomials:ring,
                    homogeneous:law.homogeneous,support:law.enclosingSupport,includesUpperBoundary:law.ownsUpperBoundary,
                    layout:layout,conditions:guards,parameterTransport:law.child.parameterTransport,proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}
