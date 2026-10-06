/// Fraction-free original Sylvester elimination over an ordered coefficient field.
package struct OriginalSingularFieldResultant {
    package static func eliminatingV<B: RationalAlgebraAdmitting>(
        _ first: OriginalSingularFieldPlanePolynomial, _ second: OriginalSingularFieldPlanePolynomial,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial {
        guard first.context === second.context else {
            throw rationalAlgebraFailure("Original field resultant needs one exact coefficient owner.")
        }
        let zero = try OriginalSingularFieldPolynomial(context: first.context, coefficients: [],
            maximumDepth: maximumDepth, usage: &usage)
        if first.isZero || second.isZero { return zero }
        let m = first.vDegree, n = second.vDegree
        guard m > 0 || n > 0 else { throw rationalAlgebraFailure("Original field resultant has two constant transverse laws.") }
        let size = try rationalAlgebraCount(m, n)
        let count = try rationalAlgebraCount(size, size, multiply: true)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldPolynomial.self, usage: &usage)
        var matrix = Array(repeating: zero, count: count)
        for row in 0..<n { for index in 0...m {
            try usage.consumeExactWork(1)
            matrix[row * size + row + index] = try OriginalSingularFieldPlaneGCD.coefficient(first,
                vPower: m - index, maximumDepth: maximumDepth, usage: &usage)
        } }
        for row in 0..<m { for index in 0...n {
            try usage.consumeExactWork(1)
            matrix[(row + n) * size + row + index] = try OriginalSingularFieldPlaneGCD.coefficient(second,
                vPower: n - index, maximumDepth: maximumDepth, usage: &usage)
        } }
        let one = try OriginalSingularFieldElement.constant(.one, in: first.context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
        var previous = try OriginalSingularFieldPolynomial(context: first.context, coefficients: [one],
            maximumDepth: maximumDepth, usage: &usage)
        var negative = false
        if size > 1 { for column in 0..<(size - 1) {
            var pivotRow: Int?
            for row in column..<size {
                try usage.consumeExactWork(1)
                if !matrix[row * size + column].isZero { pivotRow = row; break }
            }
            guard let pivotRow else { return zero }
            if pivotRow != column {
                for index in 0..<size {
                    try usage.consumeExactWork(1)
                    matrix.swapAt(column * size + index, pivotRow * size + index)
                }
                negative.toggle()
            }
            let pivot = matrix[column * size + column]
            for row in (column + 1)..<size {
                let eliminated = matrix[row * size + column]
                for index in (column + 1)..<size {
                    let numerator = try pivot.multiplied(by: matrix[row * size + index],
                        maximumDepth: maximumDepth, usage: &usage).subtracting(
                            eliminated.multiplied(by: matrix[column * size + index], maximumDepth: maximumDepth, usage: &usage),
                            maximumDepth: maximumDepth, usage: &usage)
                    let divided = try numerator.divided(by: previous, maximumDepth: maximumDepth, usage: &usage)
                    guard divided.remainder.isZero else {
                        throw rationalAlgebraFailure("Original field Bareiss division retained a nonzero remainder.")
                    }
                    matrix[row * size + index] = divided.quotient
                }
                matrix[row * size + column] = zero
            }
            previous = pivot
        } }
        let result = matrix[count - 1]
        return try negative ? result.negated(maximumDepth: maximumDepth, usage: &usage) : result
    }
}
