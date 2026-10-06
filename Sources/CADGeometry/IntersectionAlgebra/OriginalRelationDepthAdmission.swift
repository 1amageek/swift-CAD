import CADCore

/// Invocation-local enforcement of independent public relation depth limits.
package struct OriginalRelationDepthAdmission: RationalAlgebraAdmitting {
    package var base: OriginalRelationUsage
    package let maximumDepth: Int
    package let maximumCoefficientDepth: Int

    package init(base: OriginalRelationUsage, maximumDepth: Int, maximumCoefficientDepth: Int) throws {
        guard maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth) else {
            throw rationalAlgebraFailure("Original relation requires independent valid caller depth limits.")
        }
        self.base = base; self.maximumDepth = maximumDepth; self.maximumCoefficientDepth = maximumCoefficientDepth
    }
    package mutating func consumeExactWork(_ count: Int) throws { try CurrentTaskCancellationChecker().checkCancellation(); try base.consumeExactWork(count) }
    package mutating func retainExactStorage(_ count: Int) throws { try CurrentTaskCancellationChecker().checkCancellation(); try base.retainExactStorage(count) }
    package mutating func visitExactCell(depth: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard depth >= 0, depth <= maximumDepth else { throw rationalAlgebraFailure("Original relation exhausted parameter depth.") }
        try base.visitExactCell(depth: depth)
    }
    package mutating func visitCoefficientCell(depth: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard depth >= 0, depth <= maximumCoefficientDepth else { throw rationalAlgebraFailure("Original relation exhausted coefficient depth.") }
        try base.visitCoefficientCell(depth: depth)
    }
}
