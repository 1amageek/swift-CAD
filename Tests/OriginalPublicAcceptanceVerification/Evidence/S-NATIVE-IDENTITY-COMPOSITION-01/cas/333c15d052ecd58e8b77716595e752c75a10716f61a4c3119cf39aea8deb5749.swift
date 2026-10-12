#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Provider-owned validation evidence; the provider verifies its concrete family.
public struct OriginalSourceSnapshot<Source: Sendable>: Sendable {
    public let original: Source
    public let sourceDepth: Int
    public init(original: Source, sourceDepth: Int) {
        self.original = original
        self.sourceDepth = sourceDepth
    }
}
