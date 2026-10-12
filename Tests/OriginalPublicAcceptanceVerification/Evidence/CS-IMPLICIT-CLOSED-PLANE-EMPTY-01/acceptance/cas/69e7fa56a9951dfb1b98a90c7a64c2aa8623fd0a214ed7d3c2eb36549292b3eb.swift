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

public struct OriginalIssuedGeometricRelationPair: Sendable {
    public let original: OriginalIssuedGraphRelationPair
    public let geometry: ExactGeometricGraphRelation<OriginalExactScalarDomain>
    init(original: OriginalIssuedGraphRelationPair, geometry: ExactGeometricGraphRelation<OriginalExactScalarDomain>) {
        self.original = original; self.geometry = geometry
    }
}
