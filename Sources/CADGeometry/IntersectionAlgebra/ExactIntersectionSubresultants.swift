import CADCore

/// Principal Sylvester minors over the original multivariate rational ring.
package struct ExactIntersectionSubresultants: Sendable {
    private typealias Polynomial = ExactIntersectionPolynomial

    package struct PreparedPolynomial: Sendable {
        package let original: ExactIntersectionPolynomial
        package let axis: Int
        package let coefficients: [ExactIntersectionPolynomial]

        package init<B: RationalAlgebraAdmitting>(_ original: ExactIntersectionPolynomial,
            axis: Int, usage: inout B) throws {
            try intersectionAlgebraStep(&usage)
            self.original = original; self.axis = axis
            coefficients = try original.axisCoefficients(at: axis, usage: &usage)
        }
    }

    package static func principal<B: RationalAlgebraAdmitting>(
        _ first: ExactIntersectionPolynomial, _ second: ExactIntersectionPolynomial,
        axis: Int, usage: inout B) throws -> [ExactIntersectionPolynomial] {
        guard first.variableCount == second.variableCount else {
            throw rationalAlgebraFailure("Principal subresultants require the same original ring.")
        }
        let a = try PreparedPolynomial(first, axis: axis, usage: &usage)
        let b = try PreparedPolynomial(second, axis: axis, usage: &usage)
        return try principal(a, b, usage: &usage)
    }

    package static func principal<B: RationalAlgebraAdmitting>(
        _ first: PreparedPolynomial, _ second: PreparedPolynomial,
        usage: inout B) throws -> [ExactIntersectionPolynomial] {
        try intersectionAlgebraStep(&usage)
        guard first.axis == second.axis, first.original.variableCount == second.original.variableCount else {
            throw rationalAlgebraFailure("Prepared subresultants require one bound original ring and axis.")
        }
        let a = first.coefficients, b = second.coefficients
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
            let zero = try Polynomial.zero(variableCount: first.original.variableCount)
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
            result.append(try ExactIntersectionDeterminant.evaluate(&matrix, size: size, variableCount: first.original.variableCount, usage: &usage))
        }
        return result
    }

}
