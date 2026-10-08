#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public struct ExactGeometricRelationLimits: Sendable {
    public let cells: ExactRealCellLimits
    public let topology: ExactRealTopologyLimits
    public let maximumStrata: Int
    public let maximumProjectionSpans: Int
    public init(cells: ExactRealCellLimits, topology: ExactRealTopologyLimits,
                maximumStrata: Int, maximumProjectionSpans: Int) throws(ExactGeometricRelationFailure) {
        guard maximumStrata >= 0, maximumProjectionSpans >= 0 else { throw .invalidSourceBinding }
        self.cells = cells; self.topology = topology
        self.maximumStrata = maximumStrata; self.maximumProjectionSpans = maximumProjectionSpans
    }
}
