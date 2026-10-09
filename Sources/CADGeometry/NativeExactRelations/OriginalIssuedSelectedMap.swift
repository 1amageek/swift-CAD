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

/// Identifies a selected chart product without copying its source laws or cells.
public struct OriginalIssuedSelectedMap: Sendable {
    public let chartIndex: Int
    public let map: ExactParametricMap<OriginalExactScalarDomain>
    init(chartIndex: Int, map: ExactParametricMap<OriginalExactScalarDomain>) {
        self.chartIndex = chartIndex; self.map = map
    }
}
