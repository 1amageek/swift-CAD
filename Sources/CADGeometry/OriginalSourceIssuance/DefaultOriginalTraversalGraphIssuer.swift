#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Composes a curve graph without inverting its child parameter correspondence.
public struct DefaultOriginalTraversalGraphIssuer<S: OriginalTraversalSourceReading,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,E: Sendable>: OriginalTraversalGraphIssuing
    where F.Source == F.Value,S.Coefficient == F.Value {
    public typealias Source=S
    public typealias Field=F
    public typealias ChildEvidence=E
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        child: borrowing OriginalParametricGraphReceipt<S.Child,F,E>,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalParametricGraphReceipt<S,F,OriginalCurveParameterGraphEvidence<S.Child,F,E>> {
        let source=copy source,child=copy child,f=child.field
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint();try a.consumeWork(1);try source.require(limits)
                guard source.original.originalChild.owner === child.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                try child.source.require(.init(remainingSourceDepth:limits.remainingSourceDepth-1))
                let offset=try f.importing(source.original.originalStart,using:&a)
                let gain=try f.subtracting(f.importing(source.original.originalEnd,using:&a),offset,using:&a)
                let parameters=OriginalSourceParameterInterval(lower:try f.integer(0,using:&a),upper:try f.integer(1,using:&a))
                guard try f.sign(of:gain,using:&a) != .zero else { throw OriginalSourceIssuanceFailure.invalidSource }
                return try OriginalCurveParameterGraphPullback.issue(source:source,child:child,gain:gain,offset:offset,
                    support:parameters,using:&a)
            }
        } catch { throw .init(preserving:error) }
    }
}
