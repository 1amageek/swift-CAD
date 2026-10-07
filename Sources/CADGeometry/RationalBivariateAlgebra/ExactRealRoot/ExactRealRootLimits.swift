#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactRealRootLimits: Sendable {
    public let maximumRoots: Int
    /// Explicit caller policy; there is no guessed implicit enumeration ceiling.
    public init(maximumRoots: Int) throws(ExactRealRootFailure) {
        guard maximumRoots >= 0 else { throw .invalidDomain }; self.maximumRoots = maximumRoots
    }
}
