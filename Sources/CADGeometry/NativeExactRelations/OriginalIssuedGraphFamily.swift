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

/// Only complete existing cover consumers can issue a complete graph family.
public struct OriginalIssuedGraphFamily<S: Sendable,E: Sendable,C: Sendable>: Sendable {
    public let coverage: C
    public let source: OriginalSourceBinding<S>
    public let field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>
    public let graphs: [OriginalIssuedGraphPreparation<S,E>]
    public let parameterCount: Int
    public let templateCount: Int
    public let depth: ExactScalarDepth
    init(coverage:C,source:OriginalSourceBinding<S>,field:ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        graphs:[OriginalIssuedGraphPreparation<S,E>],parameterCount:Int,templateCount:Int,depth:ExactScalarDepth) {
        self.coverage=coverage;self.source=source;self.field=field;self.graphs=graphs
        self.parameterCount=parameterCount;self.templateCount=templateCount;self.depth=depth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,using a:inout A) throws(NativeExactRelationFailure) {
        do {
            try a.checkpoint()
            guard source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            guard templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
            for graph in graphs { try a.consumeWork(1);try graph.admitProof(limits:limits,using:&a) }
            try a.checkpoint()
        } catch { throw .preserving(error) }
    }
}
