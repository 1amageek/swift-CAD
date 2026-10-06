/// Exact elimination in Q[u,v][s], never an approximate resultant coefficient fit.
package struct ExactSurfaceCoefficientResultant: Sendable {
    package init() {}

    package func eliminatingParameter<B: RationalAlgebraAdmitting>(
        _ first: ExactSurfaceCoefficientPolynomial, _ second: ExactSurfaceCoefficientPolynomial,
        usage: inout B
    ) throws -> ExactBivariatePolynomial {
        if first.isZero || second.isZero { return .zero }
        let m = first.degree, n = second.degree
        let size = try rationalAlgebraCount(m, n)
        guard size > 0 else {
            throw rationalAlgebraFailure("Parameter-independent original screen equations need direct UV incidence.")
        }
        let count = try rationalAlgebraCount(size, size, multiply: true)
        try RationalAlgebraStorage.retain(count, of: ExactBivariatePolynomial.self, usage: &usage)
        var matrix = [ExactBivariatePolynomial](repeating: .zero, count: count)
        for row in 0..<n { for index in 0...m {
            try usage.consumeExactWork(1)
            matrix[row * size + row + index] = first.coefficients[m - index]
        } }
        for row in 0..<m { for index in 0...n {
            try usage.consumeExactWork(1)
            matrix[(row + n) * size + row + index] = second.coefficients[n - index]
        } }
        var previous = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        var sign = ExactRationalCoefficient.one
        if size > 1 { for column in 0..<(size - 1) {
            var pivotRow: Int?
            for row in column..<size {
                try usage.consumeExactWork(1)
                if !matrix[row * size + column].isZero { pivotRow = row; break }
            }
            guard let pivotRow else { return .zero }
            if pivotRow != column {
                for index in 0..<size {
                    try usage.consumeExactWork(1)
                    matrix.swapAt(column * size + index, pivotRow * size + index)
                }
                sign = sign.negated
            }
            let pivot = matrix[column * size + column]
            for row in (column + 1)..<size {
                let eliminated = matrix[row * size + column]
                for index in (column + 1)..<size {
                    let numerator = try pivot.multiplied(by: matrix[row * size + index], usage: &usage)
                        .subtracting(eliminated.multiplied(by: matrix[column * size + index], usage: &usage), usage: &usage)
                    matrix[row * size + index] = try numerator.dividedExactly(by: previous, usage: &usage)
                }
                matrix[row * size + column] = .zero
            }
            previous = pivot
        } }
        return try matrix[count - 1].scaled(by: sign, usage: &usage)
    }
}
