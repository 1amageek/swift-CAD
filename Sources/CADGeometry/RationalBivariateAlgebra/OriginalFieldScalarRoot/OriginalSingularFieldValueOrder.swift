import CADCore

/// Exact scalar order retaining the original values of unrelated field owners.
package enum OriginalSingularFieldValueOrder {
    package static func compare<B: RationalAlgebraAdmitting>(
        _ first: inout OriginalSingularFieldValueIsolation,
        _ second: inout OriginalSingularFieldValueIsolation, maximumDepth: Int,
        maximumCoefficientDepth: Int = 0, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try Task.checkCancellation()
        guard maximumDepth >= first.sourceDepth, maximumDepth >= second.sourceDepth,
            (0...32).contains(maximumCoefficientDepth),
            first.original.context.coefficientDepth <= maximumCoefficientDepth,
            second.original.context.coefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Original scalar order exceeds independent caller depth domains.")
        }
        var admission = Admission(base: usage, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth)
        defer { usage = admission.base }
        if try second.lower.subtracting(first.upper, usage: &admission).isPositive {
            try Task.checkCancellation(); return .negative
        }
        if try first.lower.subtracting(second.upper, usage: &admission).isPositive {
            try Task.checkCancellation(); return .positive
        }
        if first.lower == first.upper, second.lower == second.upper {
            try Task.checkCancellation()
            return .zero
        }
        var a = try OriginalSingularRationalCoordinateRoot(isolation: &first,
            maximumDepth: maximumDepth, maximumAlgebraicDepth: maximumCoefficientDepth,
            usage: &admission).endpoint
        var b = try OriginalSingularRationalCoordinateRoot(isolation: &second,
            maximumDepth: maximumDepth, maximumAlgebraicDepth: maximumCoefficientDepth,
            usage: &admission).endpoint
        let order = try ExactOrderedRealEndpoints.compare(&a, &b,
            maximumDepth: maximumDepth, usage: &admission)
        // The norm binding certifies these endpoint bounds; the existing seed
        // verifier checks them against each retained ORIGINAL selected embedding.
        first = try .init(original: first.original, lower: a.lower, upper: a.upper,
            inheritedDepth: max(first.sourceDepth, a.depth), maximumDepth: maximumDepth,
            usage: &admission)
        second = try .init(original: second.original, lower: b.lower, upper: b.upper,
            inheritedDepth: max(second.sourceDepth, b.depth), maximumDepth: maximumDepth,
            usage: &admission)
        try Task.checkCancellation()
        return order < 0 ? .negative : order > 0 ? .positive : .zero
    }

    private struct Admission<B: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
        var base: B
        let maximumDepth: Int
        let maximumCoefficientDepth: Int
        mutating func consumeExactWork(_ count: Int) throws {
            try Task.checkCancellation(); try base.consumeExactWork(count)
        }
        mutating func retainExactStorage(_ count: Int) throws {
            try Task.checkCancellation(); try base.retainExactStorage(count)
        }
        mutating func visitExactCell(depth: Int) throws {
            try Task.checkCancellation()
            guard depth >= 0, depth <= maximumDepth else {
                throw rationalAlgebraFailure("Original scalar order exhausted retained parameter depth.")
            }
            try base.visitExactCell(depth: depth)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            try Task.checkCancellation()
            guard depth >= 0, depth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("Original scalar order exhausted independent coefficient depth.")
            }
            try base.visitCoefficientCell(depth: depth)
        }
    }
}
