#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Equality of complete prepared solver inputs, without identifying authored chart sides.
public struct OriginalIssuedGraphSolverEquivalence: Sendable {
    public let originalGraph: ExactParametricGraph<OriginalExactScalarDomain>
    public let canonicalGraph: ExactParametricGraph<OriginalExactScalarDomain>
    public let originalLayout: OriginalParametricVariableLayout
    public let canonicalLayout: OriginalParametricVariableLayout
    public let predicateEquivalence: OriginalIssuedGraphPredicateEquivalence
    public let depth: ExactScalarDepth

    private init(originalGraph: ExactParametricGraph<OriginalExactScalarDomain>,
        canonicalGraph: ExactParametricGraph<OriginalExactScalarDomain>,
        originalLayout: OriginalParametricVariableLayout, canonicalLayout: OriginalParametricVariableLayout,
        predicateEquivalence:OriginalIssuedGraphPredicateEquivalence,depth: ExactScalarDepth) {
        self.originalGraph=originalGraph;self.canonicalGraph=canonicalGraph
        self.originalLayout=originalLayout;self.canonicalLayout=canonicalLayout;self.predicateEquivalence=predicateEquivalence;self.depth=depth
    }

    static func checked<S: Sendable,E: Sendable,T: Sendable,F: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ first: borrowing OriginalIssuedGraphPreparation<S,E>,
        _ second: borrowing OriginalIssuedGraphPreparation<T,F>,using admission: inout A)
        throws(NativeExactRelationFailure) -> Self? {
        let first=copy first,second=copy second
        do {
            return try admission.withProofScope() { a -> Self? in
                try a.checkpoint();try a.consumeWork(1)
                let left=first.graph,right=second.graph
                let ll=first.original.graph.layout,rl=second.original.graph.layout
                try a.admitDepth(value:first.depth.value,coefficient:first.depth.coefficient)
                try a.admitDepth(value:second.depth.value,coefficient:second.depth.coefficient)
                guard left.parameterCount == right.parameterCount,left.variableCount == right.variableCount,
                    ll.variableCount == rl.variableCount,ll.parameters.count == rl.parameters.count,
                    ll.auxiliaries.count == rl.auxiliaries.count else { return nil }
                for i in ll.parameters.indices { try a.consumeWork(1);if ll.parameters[i] != rl.parameters[i] { return nil } }
                for i in ll.auxiliaries.indices { try a.consumeWork(1);if ll.auxiliaries[i] != rl.auxiliaries[i] { return nil } }
                let field=first.field
                _=try field.importing(second.field.integer(0,using:&a),using:&a)
                guard let predicate=try OriginalIssuedGraphPredicateEquivalence.checked(left.predicate,right.predicate,field:field,using:&a) else { return nil }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self))
                let result=Self(originalGraph:copy left,canonicalGraph:copy right,
                    originalLayout:ll,canonicalLayout:rl,predicateEquivalence:predicate,depth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .preserving(error) }
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws(NativeExactRelationFailure) {
        do { try a.checkpoint();try a.admitDepth(value:depth.value,coefficient:depth.coefficient);try predicateEquivalence.admitProof(using:&a);try a.checkpoint() }
        catch { throw .preserving(error) }
    }
}
