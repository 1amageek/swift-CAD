#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellLimits: Sendable {
    public let maximumStoredCells: Int
    public let maximumRootsPerStack: Int
    public init(maximumStoredCells: Int, maximumRootsPerStack: Int) throws(ExactRealCellFailure) {
        guard maximumStoredCells >= 0, maximumRootsPerStack >= 0 else { throw .invalidDomain }
        self.maximumStoredCells = maximumStoredCells; self.maximumRootsPerStack = maximumRootsPerStack
    }
}
