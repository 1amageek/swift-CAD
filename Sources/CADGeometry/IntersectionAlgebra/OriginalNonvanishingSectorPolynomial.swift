/// Complete exclusion of original leading-coefficient roots from one closed free sector.
package struct OriginalNonvanishingSectorPolynomial: Sendable {
    package struct Exclusion: Sendable {
        package enum Side: Sendable { case beforeLower, afterUpper }
        package let root: OriginalSingularFieldRoot
        package let boundary: OriginalSingularFieldRoot
        package let side: Side
    }
    package let original: ExactIntersectionPolynomial
    package let baseCell: Int
    package let fieldPolynomial: OriginalSingularFieldPolynomial
    package let exclusions: [Exclusion]

    private init(original: ExactIntersectionPolynomial, baseCell: Int,
        fieldPolynomial: OriginalSingularFieldPolynomial, exclusions: [Exclusion]) {
        self.original = original; self.baseCell = baseCell
        self.fieldPolynomial = fieldPolynomial; self.exclusions = exclusions
    }

    /// Nil refuses this sufficient theorem; it does not classify the original relation.
    package static func prepare<B: RationalAlgebraAdmitting>(_ original: ExactIntersectionPolynomial,
        partition: OriginalRationalIntersectionCells, baseCell: Int,
        maximumDepth: Int, usage: inout B) throws -> Self? {
        try intersectionAlgebraStep(&usage)
        guard baseCell >= 0, baseCell < partition.cells.count,
            original.variableCount == partition.tower.variableCount else {
            throw rationalAlgebraFailure("Original sector nonvanishing lost its source ring or cell owner.")
        }
        let cell = partition.cells[baseCell], stack = partition.stacks[cell.stackIndex]
        guard case .sector(let lower, let upper) = cell.kind,
            cell.coordinates.count == stack.axis + 1,
            cell.admissionDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original sector nonvanishing requires one admitted complete free prefix.")
        }
        let count = stack.axis
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var prefix: [OriginalSingularFieldElement] = []; prefix.reserveCapacity(count)
        for axis in 0..<count {
            try intersectionAlgebraStep(&usage); prefix.append(cell.coordinates[axis])
        }
        guard let polynomial = try OriginalIntersectionFieldEvaluation.specialized(original,
            at: stack.axis, context: cell.context, coordinates: prefix,
            maximumDepth: maximumDepth, usage: &usage), !polynomial.isZero else { return nil }
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldPolynomial.self, usage: &usage)
        let roots = try OriginalRationalIntersectionCells.completeRootUnion(sources: [polynomial],
            inheritedDepth: max(cell.admissionDepth, cell.context.depth), maximumDepth: maximumDepth, usage: &usage)
        var exclusions: [Exclusion] = []
        for originalRoot in roots {
            var root = originalRoot
            if let lower {
                guard lower >= 0, lower < stack.roots.count else {
                    throw rationalAlgebraFailure("Original lower sector root ordinal is unbound.")
                }
                var boundary = stack.roots[lower]
                if try OriginalRationalIntersectionCells.ordered(&root, &boundary,
                    maximumDepth: maximumDepth, usage: &usage) < 0 {
                    try RationalAlgebraStorage.retain(1, of: Exclusion.self, usage: &usage)
                    exclusions.append(.init(root: root, boundary: boundary, side: .beforeLower))
                    continue
                }
            }
            if let upper {
                guard upper >= 0, upper < stack.roots.count else {
                    throw rationalAlgebraFailure("Original upper sector root ordinal is unbound.")
                }
                var boundary = stack.roots[upper]
                if try OriginalRationalIntersectionCells.ordered(&root, &boundary,
                    maximumDepth: maximumDepth, usage: &usage) > 0 {
                    try RationalAlgebraStorage.retain(1, of: Exclusion.self, usage: &usage)
                    exclusions.append(.init(root: root, boundary: boundary, side: .afterUpper))
                    continue
                }
            }
            // Equality at an endpoint is a real pole candidate, not tolerance proximity.
            return nil
        }
        return Self(original: original, baseCell: baseCell, fieldPolynomial: polynomial, exclusions: exclusions)
    }
}
