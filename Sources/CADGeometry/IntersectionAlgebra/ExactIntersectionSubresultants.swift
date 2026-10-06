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
            result.append(try ExactIntersectionDeterminant.evaluate(&matrix, size: size, variableCount: first.variableCount, usage: &usage))
        }
        return result
    }

}
