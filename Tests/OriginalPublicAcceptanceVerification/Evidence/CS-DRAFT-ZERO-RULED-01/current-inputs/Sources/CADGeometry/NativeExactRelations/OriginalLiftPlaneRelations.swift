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

/// Complete selected lift/plane source product, retaining every guarded chart and raw pair.
public struct OriginalLiftPlaneRelations<S: OriginalLiftGraphSourceReading,P: OriginalPlaneSourceReading>: OriginalIssuedGraphRelationOwning {
    public let first: OriginalRetainedSurfaceLiftDomainCover<S>
    public let firstGraphs: [OriginalIssuedGraphPreparation<S,OriginalSurfaceLiftGraphEvidence<S>>]
    public let firstReductions: [OriginalPolynomialSurfaceLiftGraphReduction<S>]
    public let firstRestrictions: [OriginalLiftPlaneParameterRestriction<S,P>]
    public let second: OriginalIssuedPlaneGraph<P>
    public let pairs: [OriginalIssuedGraphRelationPair]
    public var kind: ExactParametricRelationKind { .curveSurface }
    init(first: OriginalRetainedSurfaceLiftDomainCover<S>,firstGraphs: [OriginalIssuedGraphPreparation<S,OriginalSurfaceLiftGraphEvidence<S>>],
        firstReductions: [OriginalPolynomialSurfaceLiftGraphReduction<S>],firstRestrictions: [OriginalLiftPlaneParameterRestriction<S,P>],second: OriginalIssuedPlaneGraph<P>,pairs: [OriginalIssuedGraphRelationPair]) {
        self.first = first; self.firstGraphs = firstGraphs; self.firstReductions = firstReductions; self.firstRestrictions = firstRestrictions; self.second = second; self.pairs = pairs
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws(NativeExactRelationFailure) {
        do {
            try a.checkpoint(); try first.family.admitProof(limits:limits.source,using:&a)
            guard first.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            try second.admitProof(limits:limits,using:&a)
            for graph in firstGraphs { try a.consumeWork(1); try graph.admitProof(limits:limits,using:&a) }
            for pair in pairs { try a.consumeWork(1); try pair.relation.admitProof(using:&a) }
            try a.checkpoint()
        } catch { throw .preserving(error) }
    }
}
