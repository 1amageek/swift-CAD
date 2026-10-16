/// The derivative-closed sign condition of one retained cylindrical parent path.
package struct OriginalIntersectionCellCondition: Sendable {
    package let variableCount: Int
    package let cellIndex: Int
    package let polynomials: [ExactIntersectionPolynomial]
    package let signs: [ExactAlgebraicRealRoot.Sign]
    package let coefficientVariableCount: Int
    package let fixedCoefficientCellIndex: Int?

    package init<B: ExactScalarAdmission & ~Copyable>(partition: OriginalRationalIntersectionCells,
        cellIndex: Int, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard partition.tower.hasThomEncoding, cellIndex >= 0, cellIndex < partition.cells.count,
            partition.cells[cellIndex].coordinates.count == partition.tower.variableCount else {
            throw rationalAlgebraFailure("Cell identity requires a complete derivative-closed original parent path.")
        }
        var path: [Int] = [], current: Int? = cellIndex
        try RationalAlgebraStorage.retain(partition.tower.variableCount, of: Int.self, usage: &usage)
        path.reserveCapacity(partition.tower.variableCount)
        while let index = current {
            try intersectionAlgebraStep(&usage)
            guard path.count < partition.tower.variableCount else {
                throw rationalAlgebraFailure("Original cell identity has a cyclic or unbound parent path.")
            }
            path.append(index)
            current = partition.stacks[partition.cells[index].stackIndex].parentCell
        }
        guard path.count == partition.tower.variableCount else {
            throw rationalAlgebraFailure("Original cell identity omitted a native coordinate.")
        }
        coefficientVariableCount = partition.coefficientVariableCount
        if coefficientVariableCount > 0 {
            let prefix = path[partition.tower.variableCount - coefficientVariableCount]
            fixedCoefficientCellIndex = partition.cells[prefix].dimension == 0 ? prefix : nil
        } else { fixedCoefficientCellIndex = nil }
        var polynomials: [ExactIntersectionPolynomial] = [], signs: [ExactAlgebraicRealRoot.Sign] = []
        for (axis, index) in path.reversed().enumerated() {
            try intersectionAlgebraStep(&usage)
            let cell = partition.cells[index], stack = partition.stacks[cell.stackIndex]
            let level = partition.tower.levels[partition.tower.variableCount - 1 - axis]
            guard stack.axis == axis, cell.signs.count == level.sources.count else {
                throw rationalAlgebraFailure("Original cell identity lost its derivative sign witnesses.")
            }
            for (ordinal, source) in level.sources.enumerated() {
                try intersectionAlgebraStep(&usage)
                var duplicate = false
                for existing in polynomials.indices {
                    if try polynomials[existing].matches(source, usage: &usage) {
                        guard signs[existing] == cell.signs[ordinal] else {
                            throw rationalAlgebraFailure("Original parent-path conditions contradict the same source polynomial.")
                        }
                        duplicate = true; break
                    }
                }
                if !duplicate {
                    try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
                    try RationalAlgebraStorage.retain(1, of: ExactAlgebraicRealRoot.Sign.self, usage: &usage)
                    polynomials.append(source); signs.append(cell.signs[ordinal])
                }
            }
        }
        variableCount = partition.tower.variableCount
        self.cellIndex = cellIndex; self.polynomials = polynomials; self.signs = signs
    }

    package func contains<B: ExactScalarAdmission & ~Copyable>(context: OriginalSingularFieldContext,
        coordinates: [OriginalSingularFieldElement], maximumDepth: Int, usage: inout B) throws -> Bool {
        guard coordinates.count == variableCount else {
            throw rationalAlgebraFailure("Cell membership requires all original coordinates.")
        }
        for coordinate in coordinates {
            try intersectionAlgebraStep(&usage)
            guard coordinate.context === context else {
                throw rationalAlgebraFailure("Cell membership has a foreign original coordinate field.")
            }
        }
        for index in polynomials.indices {
            try intersectionAlgebraStep(&usage)
            let value = try OriginalIntersectionFieldEvaluation.evaluated(polynomials[index], context: context,
                coordinates: coordinates, maximumDepth: maximumDepth, usage: &usage)
            if try value.sign(maximumDepth: maximumDepth, usage: &usage) != signs[index] { return false }
        }
        return true
    }
}
