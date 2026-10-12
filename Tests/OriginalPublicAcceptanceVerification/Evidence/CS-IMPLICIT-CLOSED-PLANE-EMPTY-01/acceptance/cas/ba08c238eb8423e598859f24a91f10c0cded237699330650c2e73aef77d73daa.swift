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

/// The generic value retains both actual source snapshots, DI covers and all solved chart pairs.
public struct OriginalIssuedGeometricRelations<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable>: OriginalIssuedGeometricRelationReading {
    public let original: OriginalIssuedGraphRelations<S,E,C,T,F,D>
    public let pairs: [OriginalIssuedGeometricRelationPair]
    public let exactPoints: [OriginalIssuedExactIntersectionPoint]
    public var kind: ExactParametricRelationKind { original.kind }
    public var hasPositiveDimensionalSolutions: Bool { pairs.contains { $0.geometry.hasPositiveDimensionalSolutions } }
    public var hasPositiveDimensionalImage: Bool { pairs.contains { $0.geometry.hasPositiveDimensionalImage } }
    public var isEmpty: Bool { pairs.allSatisfy { $0.geometry.isEmpty } }
    init(original: OriginalIssuedGraphRelations<S,E,C,T,F,D>, pairs: [OriginalIssuedGeometricRelationPair], exactPoints: [OriginalIssuedExactIntersectionPoint]) {
        self.original = original; self.pairs = pairs; self.exactPoints = exactPoints
    }
}
