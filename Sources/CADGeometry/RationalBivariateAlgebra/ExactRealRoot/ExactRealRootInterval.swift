#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactRealRootInterval<Value: Sendable>: Sendable {
    public let lower: ExactRealRootBound<Value>
    public let upper: ExactRealRootBound<Value>
    public let includesLower: Bool
    public let includesUpper: Bool
    public let isEmpty: Bool
    public let depth: ExactScalarDepth
    init(lower: ExactRealRootBound<Value>, upper: ExactRealRootBound<Value>,
        includesLower: Bool, includesUpper: Bool, isEmpty: Bool, depth: ExactScalarDepth) {
        self.lower = lower; self.upper = upper; self.includesLower = includesLower
        self.includesUpper = includesUpper; self.isEmpty = isEmpty; self.depth = depth
    }
}
