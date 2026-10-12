/// Narrows coefficient precision without resetting any composing caller counter.
struct RationalCoefficientDepthAdmission<Base: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
    var base: Base
    let maximumDepth: Int

    mutating func visitExactCell(depth: Int) throws { try base.visitExactCell(depth: depth) }
    mutating func visitCoefficientCell(depth: Int) throws {
        guard depth >= 0, depth <= maximumDepth else {
            throw ExactScalarFailure.resourceLimit(.coefficientDepth)
        }
        try base.visitCoefficientCell(depth: depth)
    }
    mutating func consumeExactWork(_ count: Int) throws { try base.consumeExactWork(count) }
    mutating func retainExactStorage(_ count: Int) throws { try base.retainExactStorage(count) }
}
