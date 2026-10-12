#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain {
    func principalDeterminant<A: ExactScalarAdmission & ~Copyable>(
        _ ac: [ExactPolynomialDegreeCoefficient<F>], _ bc: [ExactPolynomialDegreeCoefficient<F>],
        m: Int, n: Int, index: Int, _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        let sum = try ExactPolynomialAccess.count(m,n), twice = try ExactPolynomialAccess.count(index,index)
        let size = sum - twice, highest = sum - index - 1
        let slots = try ExactPolynomialAccess.count(size,size,multiply:true)
        let zero = try wrap([], &usage)
        try ExactPolynomialAccess.storage(slots, Polynomial.self, &usage)
        var matrix: [Polynomial] = []; matrix.reserveCapacity(slots)
        for row in 0..<size {
            let entries = row < n-index ? ac : bc
            let shift = row < n-index ? n-index-1-row : m-index-1-(row-(n-index))
            for col in 0..<size {
                try usage.consumeWork(1)
                let degree = highest - col - shift
                matrix.append(degree >= 0 ? try coefficient(entries, degree, &usage) : zero)
            }
        }
        var previous = try constant(context.one, &usage), negative = false
        if size > 1 { for k in 0..<(size-1) {
            var pivot = k
            while pivot < size && matrix[pivot*size+k].terms.isEmpty { try usage.consumeWork(1); pivot += 1 }
            if pivot == size { return zero }
            if pivot != k {
                try usage.consumeWork(size)
                for col in 0..<size { matrix.swapAt(k*size+col,pivot*size+col) }; negative.toggle()
            }
            let diagonal = matrix[k*size+k]
            for i in (k+1)..<size {
                let left = matrix[i*size+k]
                for col in (k+1)..<size {
                    let numerator = try subtracting(multiplying(diagonal,matrix[i*size+col],&usage),
                        multiplying(left,matrix[k*size+col],&usage), &usage)
                    matrix[i*size+col] = try exactDivide(numerator,previous,&usage)
                }
                matrix[i*size+k] = zero
            }
            previous = diagonal
        } }
        return try negative ? negated(matrix[slots-1], &usage) : matrix[slots-1]
    }
}
