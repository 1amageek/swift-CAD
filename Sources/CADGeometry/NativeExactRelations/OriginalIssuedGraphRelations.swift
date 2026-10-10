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

public struct OriginalIssuedGraphRelations<S: Sendable,E: Sendable,C: Sendable,T: Sendable,F: Sendable,D: Sendable>: OriginalIssuedGraphRelationOwning {
    public let first:OriginalIssuedGraphFamily<S,E,C>
    public let second:OriginalIssuedGraphFamily<T,F,D>
    public let kind:ExactParametricRelationKind
    public let pairs:[OriginalIssuedGraphRelationPair]
    init(first:OriginalIssuedGraphFamily<S,E,C>,second:OriginalIssuedGraphFamily<T,F,D>,kind:ExactParametricRelationKind,pairs:[OriginalIssuedGraphRelationPair]) {
        self.first=first;self.second=second;self.kind=kind;self.pairs=pairs
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalDomainIdentityLimits,using a:inout A) throws(NativeExactRelationFailure) {
        do {
            try a.checkpoint();try first.admitProof(limits:limits,using:&a);try second.admitProof(limits:limits,using:&a)
            for pair in pairs { try a.consumeWork(1);try pair.relation.admitProof(using:&a) }
            try a.checkpoint()
        } catch { throw .preserving(error) }
    }

}
