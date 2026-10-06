import CADCore

/// Principal Sylvester minors over the original multivariate rational ring.
package struct ExactIntersectionSubresultants: Sendable {
    private typealias Polynomial = ExactIntersectionPolynomial

    package static func principal<B: RationalAlgebraAdmitting>(
        _ first: ExactIntersectionPolynomial, _ second: ExactIntersectionPolynomial,
        axis: Int, usage: inout B) throws -> [ExactIntersectionPolynomial] {
        guard first.variableCount == second.variableCount else {
            throw rationalAlgebraFailure("Principal subresultants require the same original ring.")
        }
        let a = try first.axisCoefficients(at: axis, usage: &usage)
        let b = try second.axisCoefficients(at: axis, usage: &usage)
        if a.isEmpty || b.isEmpty { return [] }
        let m = a.count - 1, n = b.count - 1
        let count = try rationalAlgebraCount(min(m, n), 1)
        try RationalAlgebraStorage.retain(count, of: Polynomial.self, usage: &usage)
        var result: [Polynomial] = []; result.reserveCapacity(count)
        for index in 0..<count {
            try intersectionAlgebraStep(&usage)
            let aRows = n - index, bRows = m - index
            let size = try rationalAlgebraCount(aRows, bRows)
            let slots = try rationalAlgebraCount(size, size, multiply: true)
            let zero = try Polynomial.zero(variableCount: first.variableCount)
            try RationalAlgebraStorage.retain(slots, of: Polynomial.self, usage: &usage)
            var matrix = Array(repeating: zero, count: slots)
            for row in 0..<aRows {
                for offset in 0...m {
                    try intersectionAlgebraStep(&usage)
                    let column = try rationalAlgebraCount(row, offset)
                    if column < size { matrix[row * size + column] = a[m - offset] }
                }
            }
            for row in 0..<bRows {
                for offset in 0...n {
                    try intersectionAlgebraStep(&usage)
                    let column = try rationalAlgebraCount(row, offset)
                    if column < size { matrix[(aRows + row) * size + column] = b[n - offset] }
                }
            }
            result.append(try determinant(&matrix, size: size, ring: first.variableCount, usage: &usage))
        }
        return result
    }

    private static func determinant<B: RationalAlgebraAdmitting>(_ matrix: inout [Polynomial],
        size: Int, ring: Int, usage: inout B) throws -> Polynomial {
        var previous = try Polynomial.constant(variableCount: ring, value: .one, usage: &usage)
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
                guard let pivotRow else { return try .zero(variableCount: ring) }
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
                    matrix[row * size + column] = try .zero(variableCount: ring)
                }
                previous = pivot
            }
        }
        return try matrix[matrix.count - 1].scaled(by: sign, usage: &usage)
    }
}
