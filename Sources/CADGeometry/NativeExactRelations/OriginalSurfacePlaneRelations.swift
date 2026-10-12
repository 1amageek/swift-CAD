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

/// Complete original surface-chart/plane product in the caller's source order.
public struct OriginalSurfacePlaneRelations<S: Sendable, E: Sendable, C: Sendable,
    P: OriginalPlaneSourceReading>: OriginalIssuedGraphRelationOwning {
    public let surface: OriginalIssuedGraphFamily<S,E,C>
    public let plane: OriginalIssuedPlaneGraph<P>
    public let planeFirst: Bool
    public let pairs: [OriginalIssuedGraphRelationPair]
    public var kind: ExactParametricRelationKind { .surfaceSurface }

    init(surface: OriginalIssuedGraphFamily<S,E,C>, plane: OriginalIssuedPlaneGraph<P>,
        planeFirst: Bool, pairs: [OriginalIssuedGraphRelationPair]) {
        self.surface = surface
        self.plane = plane
        self.planeFirst = planeFirst
        self.pairs = pairs
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(
        limits: OriginalDomainIdentityLimits, using a: inout A) throws(NativeExactRelationFailure) {
        do {
            try a.checkpoint()
            try surface.admitProof(limits: limits, using: &a)
            try plane.admitProof(limits: limits, using: &a)
            for pair in pairs {
                try a.consumeWork(1)
                try pair.relation.admitProof(using: &a)
            }
            try a.checkpoint()
        } catch { throw .preserving(error) }
    }
}
