import CADCore

/// Invocation-local causal depth mapping for an exact retained scalar source.
package struct OriginalSourceScalarAdmission<B: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
    package var base: B
    package let maximumDepth: Int
    package let maximumCoefficientDepth: Int
    package let originalParameterDepth: Int
    package let originalCoefficientDepth: Int
    package let inheritedParameterDepth: Int
    package let inheritedCoefficientDepth: Int
    package var parameterDepth: Int
    package var coefficientDepth: Int
    package var mapsOriginalCoefficientDepth = true
    package mutating func consumeExactWork(_ count: Int) throws {
        try Task.checkCancellation(); try base.consumeExactWork(count)
    }
    package mutating func retainExactStorage(_ count: Int) throws {
        try Task.checkCancellation(); try base.retainExactStorage(count)
    }
    package mutating func visitExactCell(depth: Int) throws {
        try Task.checkCancellation()
        let mapped = try rationalAlgebraCount(inheritedParameterDepth, max(0, depth - originalParameterDepth))
        guard depth >= 0, mapped <= maximumDepth else {
            throw rationalAlgebraFailure("Original coefficient source exhausted parameter root depth.")
        }
        parameterDepth = max(parameterDepth, mapped); try base.visitExactCell(depth: mapped)
    }
    package mutating func visitCoefficientCell(depth: Int) throws {
        try Task.checkCancellation()
        let mapped = mapsOriginalCoefficientDepth
            ? try rationalAlgebraCount(inheritedCoefficientDepth, max(0, depth - originalCoefficientDepth)) : depth
        guard depth >= 0, mapped <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Original coefficient transport exhausted coefficient root depth.")
        }
        coefficientDepth = max(coefficientDepth, mapped); try base.visitCoefficientCell(depth: mapped)
    }
}
