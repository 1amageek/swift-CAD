#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain: ExactPolynomialEliminating {
    public func resultant<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing Polynomial,
        _ second: borrowing Polynomial, eliminating variable: Int,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy first, copy second) { usage in
            try requireVariable(variable)
            guard let m = try degree(first, variable, &usage), let n = try degree(second, variable, &usage) else {
                return try wrap([], &usage)
            }
            let size = try ExactPolynomialAccess.count(m, n)
            if size == 0 { return try constant(context.one, &usage) }
            let slots = try ExactPolynomialAccess.count(size, size, multiply: true)
            try ExactPolynomialAccess.storage(slots, Polynomial.self, &usage)
            try usage.consumeWork(slots)
            let zero = try wrap([], &usage)
            var matrix = [Polynomial](repeating: zero, count: slots)
            let a = try coefficients(first, variable, &usage), b = try coefficients(second, variable, &usage)
            for row in 0..<n { for col in 0...m {
                matrix[row * size + row + col] = try coefficient(a, m - col, &usage)
            } }
            for row in 0..<m { for col in 0...n {
                matrix[(row + n) * size + row + col] = try coefficient(b, n - col, &usage)
            } }
            var previous = try constant(context.one, &usage), negative = false
            if size > 1 { for pivot in 0..<(size - 1) {
                var row = pivot
                while row < size && matrix[row * size + pivot].terms.isEmpty { try usage.consumeWork(1); row += 1 }
                if row == size { return try wrap([], &usage) }
                if row != pivot {
                    try usage.consumeWork(size)
                    for col in 0..<size { matrix.swapAt(row * size + col, pivot * size + col) }
                    negative.toggle()
                }
                let diagonal = matrix[pivot * size + pivot]
                for i in (pivot + 1)..<size {
                    let left = matrix[i * size + pivot]
                    for j in (pivot + 1)..<size {
                        let numerator = try subtracting(multiplying(diagonal, matrix[i * size + j], &usage),
                            multiplying(left, matrix[pivot * size + j], &usage), &usage)
                        matrix[i * size + j] = try exactDivide(numerator, previous, &usage)
                    }
                    matrix[i * size + pivot] = zero
                }
                previous = diagonal
            } }
            let result = negative ? try negated(matrix[slots - 1], &usage) : matrix[slots - 1]
            let eliminatedDegree = try degree(result, variable, &usage)
            guard eliminatedDegree == nil || eliminatedDegree == 0 else {
                throw ExactPolynomialFailure.invalidCertificate
            }
            return try wrap(result.terms, &usage)
        }
    }
}
