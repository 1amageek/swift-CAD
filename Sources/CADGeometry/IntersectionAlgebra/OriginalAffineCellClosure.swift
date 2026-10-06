/// Exact weak polyhedron closure proved by affine segments to the source cell.
package struct OriginalAffineCellClosure: Sendable {
    package let includedCells: [Int]
    private init(includedCells: [Int]) { self.includedCells = includedCells }

    package static func prepare<B: RationalAlgebraAdmitting>(partition: OriginalRationalIntersectionCells,
        source: OriginalIntersectionCellCondition, maximumDepth: Int, usage: inout B) throws -> Self? {
        try intersectionAlgebraStep(&usage)
        guard source.variableCount == partition.tower.variableCount,
            source.cellIndex >= 0, source.cellIndex < partition.cells.count,
            partition.cells[source.cellIndex].coordinates.count == source.variableCount,
            maximumDepth >= 0, partition.cells[source.cellIndex].admissionDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Affine closure requires its complete original source cell and caller depth.")
        }
        let bound = try OriginalIntersectionCellCondition(partition: partition, cellIndex: source.cellIndex, usage: &usage)
        guard bound.signs == source.signs, bound.polynomials.count == source.polynomials.count,
            bound.coefficientVariableCount == source.coefficientVariableCount,
            bound.fixedCoefficientCellIndex == source.fixedCoefficientCellIndex else {
            throw rationalAlgebraFailure("Affine closure has a foreign source-cell sign condition.")
        }
        for index in bound.polynomials.indices {
            guard try bound.polynomials[index].matches(source.polynomials[index], usage: &usage) else {
                throw rationalAlgebraFailure("Affine closure has a foreign source polynomial condition.")
            }
        }
        guard partition.excludedPrefixes.isEmpty else { return nil }
        let coefficientCount = source.coefficientVariableCount
        if coefficientCount > 0 && source.fixedCoefficientCellIndex == nil { return nil }
        try RationalAlgebraStorage.retain(source.polynomials.count, of: Bool.self, usage: &usage)
        var fixedConditions: [Bool] = []; fixedConditions.reserveCapacity(source.polynomials.count)
        for polynomial in source.polynomials {
            var constantOnFiber = true
            for term in try polynomial.orderedTerms(usage: &usage) {
                var degree = 0
                for axis in coefficientCount..<source.variableCount {
                    try intersectionAlgebraStep(&usage)
                    degree = try rationalAlgebraCount(degree, term.key.exponent(at: axis))
                    if degree > 1 { return nil }
                }
                if degree > 0 { constantOnFiber = false }
            }
            fixedConditions.append(constantOnFiber)
        }
        var included: [Int] = []
        for index in partition.cells.indices where partition.cells[index].coordinates.count == source.variableCount {
            try intersectionAlgebraStep(&usage)
            let target = try OriginalIntersectionCellCondition(partition: partition, cellIndex: index, usage: &usage)
            if coefficientCount > 0, target.fixedCoefficientCellIndex != source.fixedCoefficientCellIndex { continue }
            guard source.signs.count == target.signs.count else {
                throw rationalAlgebraFailure("Affine closure has unrelated original sign witnesses.")
            }
            var compatible = true
            for ordinal in source.signs.indices {
                try intersectionAlgebraStep(&usage)
                if fixedConditions[ordinal] {
                    compatible = source.signs[ordinal] == target.signs[ordinal]
                    if !compatible { break }
                    continue
                }
                switch source.signs[ordinal] {
                case .zero: compatible = target.signs[ordinal] == .zero
                case .positive: compatible = target.signs[ordinal] != .negative
                case .negative: compatible = target.signs[ordinal] != .positive
                }
                if !compatible { break }
            }
            if compatible {
                guard partition.cells[index].admissionDepth <= maximumDepth,
                    partition.cells[index].coefficientAdmissionDepth <= partition.maximumCoefficientDepth else {
                    throw rationalAlgebraFailure("Affine closure cannot reset its original cell depth.")
                }
                try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                included.append(index)
            }
        }
        return Self(includedCells: included)
    }
}
