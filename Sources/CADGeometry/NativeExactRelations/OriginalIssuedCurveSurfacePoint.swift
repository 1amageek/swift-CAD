#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI
import SourceIssuer
import OriginalCoordinateTransfer
#endif

/// Read-only original tuple and every exact source-chart incidence for that tuple.
public struct OriginalIssuedCurveSurfacePoint: Sendable {
    public let t: OriginalExactScalar
    public let u: OriginalExactScalar
    public let v: OriginalExactScalar
    public let incidenceRange: Range<Int>
    init(t: OriginalExactScalar, u: OriginalExactScalar, v: OriginalExactScalar, incidenceRange: Range<Int>) {
        self.t = t; self.u = u; self.v = v; self.incidenceRange = incidenceRange
    }
}
