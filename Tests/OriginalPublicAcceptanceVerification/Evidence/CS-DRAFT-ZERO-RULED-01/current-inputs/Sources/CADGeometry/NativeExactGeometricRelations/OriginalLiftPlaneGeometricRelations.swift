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

/// Source-owned lift/whole-plane points, strata and all original parameter/auxiliary fibers.
public struct OriginalLiftPlaneGeometricRelations<S: OriginalLiftGraphSourceReading,P: OriginalPlaneSourceReading>: OriginalIssuedGeometricRelationReading {
    public let original: OriginalLiftPlaneRelations<S,P>
    public let pairs: [OriginalIssuedGeometricRelationPair]
    public let exactPoints: [OriginalIssuedExactIntersectionPoint]
    public var kind: ExactParametricRelationKind { .curveSurface }
    public var hasPositiveDimensionalSolutions: Bool { pairs.contains { $0.geometry.hasPositiveDimensionalSolutions } }
    public var hasPositiveDimensionalImage: Bool { pairs.contains { $0.geometry.hasPositiveDimensionalImage } }
    public var isEmpty: Bool { pairs.allSatisfy { $0.geometry.isEmpty } }
    init(original: OriginalLiftPlaneRelations<S,P>,pairs: [OriginalIssuedGeometricRelationPair],exactPoints: [OriginalIssuedExactIntersectionPoint]) {
        self.original = original; self.pairs = pairs; self.exactPoints = exactPoints
    }
}
