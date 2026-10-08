#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Ordinals are local to their retained result, never cross-result identity.
public struct ExactGeometricStratumRecord: Sendable, BitwiseCopyable {
    public let ordinal: Int
    public let sourceComponentOrdinal: Int
    public let parameterDimension: Int
    public let imageDimension: Int
    public let fiberDimension: Int
}
