#if ISSUED_GEOMETRY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import L6
import DI0
import DI
import SourceIssuer
import IssuedGraphs
#endif

/// Immutable owner of every source chart, original UV, auxiliary and image stratum.
public struct OriginalSurfacePlaneGeometricRelations<S: Sendable, E: Sendable, C: Sendable,
    P: OriginalPlaneSourceReading>: OriginalIssuedGeometricRelationReading {
    public let original: OriginalSurfacePlaneRelations<S,E,C,P>
    public let pairs: [OriginalIssuedGeometricRelationPair]
    public let exactPoints: [OriginalIssuedExactIntersectionPoint]
    public var kind: ExactParametricRelationKind { .surfaceSurface }
    public var hasPositiveDimensionalSolutions: Bool { pairs.contains { $0.geometry.hasPositiveDimensionalSolutions } }
    public var hasPositiveDimensionalImage: Bool { pairs.contains { $0.geometry.hasPositiveDimensionalImage } }
    public var isEmpty: Bool { pairs.allSatisfy { $0.geometry.isEmpty } }

    init(original: OriginalSurfacePlaneRelations<S,E,C,P>,
        pairs: [OriginalIssuedGeometricRelationPair], exactPoints: [OriginalIssuedExactIntersectionPoint]) {
        self.original = original
        self.pairs = pairs
        self.exactPoints = exactPoints
    }
}
