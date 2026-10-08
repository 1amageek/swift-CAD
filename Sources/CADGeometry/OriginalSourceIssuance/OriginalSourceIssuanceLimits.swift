/// Source depth is independent from the caller's L0 work/storage/scalar depths.
public struct OriginalSourceIssuanceLimits: Sendable {
    public let remainingSourceDepth: Int
    public init(remainingSourceDepth: Int) throws(OriginalSourceIssuanceFailure) {
        guard remainingSourceDepth >= 0 else { throw .invalidSource }
        self.remainingSourceDepth = remainingSourceDepth
    }
}
