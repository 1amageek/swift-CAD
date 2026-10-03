/// Invocation-wide boundary comparison admission, independent of geometric tolerance.
public struct SolidComplexValidationOptions: Equatable, Sendable {
    public let maximumEdgeComparisons: Int

    public init(maximumEdgeComparisons: Int = 1_000_000) {
        self.maximumEdgeComparisons = maximumEdgeComparisons
    }
}
