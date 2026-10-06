import CADCore

/// Exact Sylvester elimination with fraction-free Bareiss updates in Q[u].
public struct ExactBivariateResultant: Sendable {
    public init() {}

    public func eliminatingV<B: RationalAlgebraAdmitting>(_ first: ExactBivariatePolynomial,
        _ second: ExactBivariatePolynomial, usage: inout B) throws -> ExactBivariatePolynomial {
        if first.isZero || second.isZero { return .zero }
        let m = first.vDegree, n = second.vDegree
        if m == 0, n == 0 {
            throw rationalAlgebraFailure("A zero-degree pair has no unique Sylvester elimination authority.")
        }
        let size = try rationalAlgebraCount(m, n)
        let count = try rationalAlgebraCount(size, size, multiply: true)
        try RationalAlgebraStorage.retain(count, of: ExactBivariatePolynomial.self, usage: &usage)
        var matrix = [ExactBivariatePolynomial](repeating: .zero, count: count)
        for row in 0..<n { for i in 0...m {
            try usage.consumeExactWork(1)
            matrix[row * size + row + i] = try first.coefficient(ofV: m - i, usage: &usage)
        } }
        for row in 0..<m { for i in 0...n {
            try usage.consumeExactWork(1)
            matrix[(row + n) * size + row + i] = try second.coefficient(ofV: n - i, usage: &usage)
        } }
        var previous = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        var sign = ExactRationalCoefficient.one
        if size > 1 { for column in 0..<(size - 1) {
            try Task.checkCancellation()
            var pivotRow: Int?
            for row in column..<size {
                try usage.consumeExactWork(1)
                if !matrix[row * size + column].isZero { pivotRow = row; break }
            }
            guard let pivotRow else { return .zero }
            if pivotRow != column {
                for j in 0..<size {
                    try usage.consumeExactWork(1)
                    matrix.swapAt(column * size + j, pivotRow * size + j)
                }
                sign = sign.negated
            }
            let pivot = matrix[column * size + column]
            for row in (column + 1)..<size {
                let eliminated = matrix[row * size + column]
                for j in (column + 1)..<size {
                    let numerator = try pivot.multiplied(by: matrix[row * size + j], usage: &usage)
                        .subtracting(eliminated.multiplied(by: matrix[column * size + j], usage: &usage), usage: &usage)
                    matrix[row * size + j] = try numerator.dividedExactly(by: previous, usage: &usage)
                }
                matrix[row * size + column] = .zero
            }
            previous = pivot
        } }
        return try matrix[count - 1].scaled(by: sign, usage: &usage)
    }
}
