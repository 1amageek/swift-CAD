import CADCore

/// Exact scalar order retaining the original values of unrelated field owners.
package enum OriginalSingularFieldValueOrder {
    package static func compare<B: ExactScalarAdmission & ~Copyable>(
        _ first: inout OriginalSingularFieldValueIsolation,
        _ second: inout OriginalSingularFieldValueIsolation, maximumDepth: Int,
        maximumCoefficientDepth: Int = 0, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard maximumDepth >= first.sourceDepth, maximumDepth >= second.sourceDepth,
            (0...32).contains(maximumCoefficientDepth),
            first.original.context.coefficientDepth <= maximumCoefficientDepth,
            second.original.context.coefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Original scalar order exceeds independent caller depth domains.")
        }
        return try usage.withProofScope(maximum: .init(value: maximumDepth,
            coefficient: maximumCoefficientDepth)) { usage in
            if try second.lower.subtracting(first.upper, usage: &usage).isPositive {
                try CurrentTaskCancellationChecker().checkCancellation(); return .negative
            }
            if try first.lower.subtracting(second.upper, usage: &usage).isPositive {
                try CurrentTaskCancellationChecker().checkCancellation(); return .positive
            }
            if first.lower == first.upper, second.lower == second.upper {
                try CurrentTaskCancellationChecker().checkCancellation()
                return .zero
            }
            var a = try OriginalSingularRationalCoordinateRoot(isolation: &first,
                maximumDepth: maximumDepth, maximumAlgebraicDepth: maximumCoefficientDepth,
                usage: &usage).endpoint
            var b = try OriginalSingularRationalCoordinateRoot(isolation: &second,
                maximumDepth: maximumDepth, maximumAlgebraicDepth: maximumCoefficientDepth,
                usage: &usage).endpoint
            let order = try ExactOrderedRealEndpoints.compare(&a, &b,
                maximumDepth: maximumDepth, usage: &usage)
            // The norm binding certifies these endpoint bounds; the existing seed
            // verifier checks them against each retained ORIGINAL selected embedding.
            first = try .init(original: first.original, lower: a.lower, upper: a.upper,
                inheritedDepth: max(first.sourceDepth, a.depth), maximumDepth: maximumDepth,
                usage: &usage)
            second = try .init(original: second.original, lower: b.lower, upper: b.upper,
                inheritedDepth: max(second.sourceDepth, b.depth), maximumDepth: maximumDepth,
                usage: &usage)
            try CurrentTaskCancellationChecker().checkCancellation()
            return order < 0 ? .negative : order > 0 ? .positive : .zero
        }
    }
}
