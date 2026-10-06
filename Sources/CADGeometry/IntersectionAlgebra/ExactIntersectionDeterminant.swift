import CADCore

/// Fraction-free exact determinant over one original rational polynomial ring.
package enum ExactIntersectionDeterminant {
    private typealias Polynomial = ExactIntersectionPolynomial
    package static func evaluate<B: RationalAlgebraAdmitting>(_ matrix: inout [ExactIntersectionPolynomial],
        size: Int, variableCount: Int, usage: inout B) throws -> ExactIntersectionPolynomial {
        guard size >= 0, (1...5).contains(variableCount),
              matrix.count == (try rationalAlgebraCount(size, size, multiply: true)) else {
            throw rationalAlgebraFailure("Exact determinant requires a bound square original polynomial matrix.")
        }
        for value in matrix {
            try intersectionAlgebraStep(&usage)
            guard value.variableCount == variableCount else {
                throw rationalAlgebraFailure("Exact determinant entries do not share one original ring.")
            }
        }
        var previous = try Polynomial.constant(variableCount: variableCount, value: .one, usage: &usage)
        if size == 0 { return previous }
        var sign = ExactRationalCoefficient.one
        if size > 1 {
            for column in 0..<(size - 1) {
                try intersectionAlgebraStep(&usage)
                var pivotRow: Int?
                for row in column..<size {
                    try intersectionAlgebraStep(&usage)
                    if !matrix[row * size + column].isZero { pivotRow = row; break }
                }
                guard let pivotRow else { return try .zero(variableCount: variableCount) }
                if pivotRow != column {
                    for j in 0..<size {
                        try intersectionAlgebraStep(&usage)
                        matrix.swapAt(column * size + j, pivotRow * size + j)
                    }
                    sign = sign.negated
                }
                let pivot = matrix[column * size + column]
                for row in (column + 1)..<size {
                    let eliminated = matrix[row * size + column]
                    for j in (column + 1)..<size {
                        try intersectionAlgebraStep(&usage)
                        let numerator = try pivot.multiplied(by: matrix[row * size + j], usage: &usage)
                            .subtracting(eliminated.multiplied(by: matrix[column * size + j], usage: &usage),
                                         usage: &usage)
                        matrix[row * size + j] = try numerator.dividedExactly(by: previous, usage: &usage)
                    }
                    matrix[row * size + column] = try .zero(variableCount: variableCount)
                }
                previous = pivot
            }
        }
        return try matrix[matrix.count - 1].scaled(by: sign, usage: &usage)
    }
}
