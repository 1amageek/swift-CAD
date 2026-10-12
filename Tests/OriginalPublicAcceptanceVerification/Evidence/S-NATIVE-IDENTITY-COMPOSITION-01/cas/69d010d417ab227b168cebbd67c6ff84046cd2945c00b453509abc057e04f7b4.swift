/// An exact value retaining its original immutable field and attained depths.
public struct OriginalExactScalar: Sendable {
    let original: OriginalSingularFieldElement
    public let depth: ExactScalarDepth
    init(original: OriginalSingularFieldElement, depth: ExactScalarDepth) {
        self.original = original; self.depth = depth
    }
}
