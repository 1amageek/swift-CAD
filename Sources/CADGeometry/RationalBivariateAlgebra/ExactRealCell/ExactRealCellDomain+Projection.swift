#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain {
    func coefficientVector(_ law: Polynomial, axis: Int, _ a: inout ExactCellBorrowedAdmission) throws -> [Polynomial] {
        guard let degree = try polynomials.degree(of: law, in: axis, using: &a) else { return [] }
        let count = try ExactCellAccess.add(degree, 1)
        try ExactCellAccess.storage(count, Polynomial.self, &a)
        if degree == 0 { return [law] }
        try ExactCellAccess.storage(count, Int.self, &a)
        var counts = Array(repeating: 0, count: count)
        for term in law.terms {
            try a.consumeWork(1)
            counts[term.powers[axis]] = try ExactCellAccess.add(counts[term.powers[axis]], 1)
        }
        try ExactCellAccess.storage(count, [ExactPolynomialTerm<Field.Value>].self, &a)
        try ExactCellAccess.storage(law.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
        var buckets = Array(repeating: [ExactPolynomialTerm<Field.Value>](), count: count)
        for index in counts.indices { try a.consumeWork(1); buckets[index].reserveCapacity(counts[index]) }
        for term in law.terms {
            try a.consumeWork(1)
            try ExactCellAccess.storage(term.powers.count, Int.self, &a)
            try a.consumeWork(term.powers.count)
            var powers = term.powers; powers[axis] = 0
            buckets[term.powers[axis]].append(.init(powers: powers, coefficient: term.coefficient))
        }
        var result: [Polynomial] = []; result.reserveCapacity(count)
        for terms in buckets {
            result.append(try polynomials.polynomial(terms: terms, using: &a))
        }
        return result
    }
    func insert(_ law: Polynomial, into result: inout [Polynomial], _ a: inout ExactCellBorrowedAdmission) throws {
        guard !law.terms.isEmpty else { return }
        var nonconstant = false
        for term in law.terms {
            try a.consumeWork(term.powers.count)
            for power in term.powers where power != 0 { nonconstant = true }
        }
        if !nonconstant { return }
        let normalized = law
        for existing in result { if try polynomials.equals(existing, normalized, using: &a) { return } }
        try ExactCellAccess.storage(1, Polynomial.self, &a); result.append(normalized)
    }
    func determinant(_ input: [Polynomial], size: Int, _ a: inout ExactCellBorrowedAdmission) throws -> Polynomial {
        if size == 0 { return try polynomials.constant(context.field.integer(1, using: &a), using: &a) }
        let slots = try ExactCellAccess.multiply(size, size)
        guard input.count == slots else { throw ExactRealCellFailure.invalidCoverage }
        try ExactCellAccess.storage(slots, Polynomial.self, &a)
        var matrix = input
        var previous = try polynomials.constant(context.field.integer(1, using: &a), using: &a), negative = false
        if size > 1 { for k in 0..<(size-1) {
            var pivot = k
            while try pivot < size && polynomials.isZero(matrix[pivot*size+k], using: &a) { try a.consumeWork(1); pivot += 1 }
            if pivot == size { return try polynomials.zero(using: &a) }
            if pivot != k {
                try a.consumeWork(size)
                for j in 0..<size { matrix.swapAt(k*size+j, pivot*size+j) }; negative.toggle()
            }
            let diagonal = matrix[k*size+k]
            for i in (k+1)..<size {
                let left = matrix[i*size+k]
                for j in (k+1)..<size {
                    let n = try polynomials.subtracting(polynomials.multiplying(diagonal, matrix[i*size+j], using: &a),
                        polynomials.multiplying(left, matrix[k*size+j], using: &a), using: &a)
                    matrix[i*size+j] = try polynomials.dividedExactly(n, by: previous, using: &a)
                }
                matrix[i*size+k] = try polynomials.zero(using: &a)
            }
            previous = diagonal
        } }
        return try negative ? polynomials.negated(matrix[slots-1], using: &a) : matrix[slots-1]
    }
    func principal(_ first: Polynomial, _ second: Polynomial, axis: Int, index: Int,
        _ a: inout ExactCellBorrowedAdmission) throws -> Polynomial {
        guard let m = try polynomials.degree(of: first, in: axis, using: &a),
            let n = try polynomials.degree(of: second, in: axis, using: &a), index >= 0, index < min(m,n)
            else { throw ExactRealCellFailure.invalidVariable }
        return try principal(firstCoefficients: coefficientVector(first, axis: axis, &a),
            secondCoefficients: coefficientVector(second, axis: axis, &a), index: index, &a)
    }
    func principal(firstCoefficients ac: [Polynomial], secondCoefficients bc: [Polynomial], index: Int,
        _ a: inout ExactCellBorrowedAdmission) throws -> Polynomial {
        let m = ac.count-1, n = bc.count-1
        guard index >= 0, index < min(m,n) else { throw ExactRealCellFailure.invalidVariable }
        let sum = try ExactCellAccess.add(m,n), twice = try ExactCellAccess.multiply(index,2)
        let size = sum-twice, highest = sum-index-1
        let zero = try polynomials.zero(using: &a)
        try ExactCellAccess.storage(ExactCellAccess.multiply(size,size), Polynomial.self, &a)
        var matrix: [Polynomial] = []; matrix.reserveCapacity(try ExactCellAccess.multiply(size,size))
        for row in 0..<size {
            let entries = row < n-index ? ac : bc
            let shift = row < n-index ? n-index-1-row : m-index-1-(row-(n-index))
            for col in 0..<size {
                try a.consumeWork(1)
                let degree = highest-col-shift
                matrix.append(degree >= 0 && degree < entries.count ? entries[degree] : zero)
            }
        }
        return try determinant(matrix, size: size, &a)
    }
    func projection(_ source: ExactRealCellSource<Base>, _ a: inout ExactCellBorrowedAdmission) throws -> [ExactRealCellProjectionLevel<Base>] {
        try require(source, &a)
        var pending: [Polynomial] = []
        for law in source.polynomials { try insert(law, into: &pending, &a) }
        for axis in source.domains.indices {
            let domain = source.domains[axis]
            try ExactCellAccess.storage(2, ExactRealRootBound<Field.Value>.self, &a)
            for bound in [domain.lower, domain.upper] {
                if case .finite(let value) = bound {
                    let law = try polynomials.subtracting(polynomials.variable(axis, using: &a), polynomials.constant(context.field.importing(value,using:&a), using: &a), using: &a)
                    try insert(law, into: &pending, &a)
                }
            }
        }
        try ExactCellAccess.storage(source.variableCount, ExactRealCellProjectionLevel<Base>.self, &a)
        var descending: [ExactRealCellProjectionLevel<Base>] = []
        for axis in (0..<source.variableCount).reversed() {
            var laws: [Polynomial] = []
            for law in pending { try insert(law, into: &laws, &a) }
            let cutLawCount = laws.count
            var witnesses: [ExactRealCellProjectionWitness<Base>] = []
            var offset = 0
            while offset < laws.count {
                let law = laws[offset]; offset += 1
                let d = try polynomials.differentiated(law, in: axis, using: &a)
                try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                witnesses.append(.derivative(original: law, result: d, axis: axis))
                try insert(d, into: &laws, &a)
            }
            var lower: [Polynomial] = [], coefficients: [[Polynomial]] = [], families: [[Polynomial]] = []
            try ExactCellAccess.storage(laws.count, [Polynomial].self, &a)
            try ExactCellAccess.storage(laws.count, [Polynomial].self, &a)
            for law in laws {
                let cs = try coefficientVector(law, axis: axis, &a); coefficients.append(cs)
                for degree in cs.indices {
                    try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                    witnesses.append(.coefficient(original: law, result: cs[degree], axis: axis, degree: degree))
                    try insert(cs[degree], into: &lower, &a)
                }
                var reducta: [Polynomial] = [], remainder = law
                while let degree = try polynomials.degree(of: remainder, in: axis, using: &a), degree > 0 {
                    try ExactCellAccess.storage(1, Polynomial.self, &a); reducta.append(remainder)
                    let derivative = try polynomials.differentiated(remainder, in: axis, using: &a)
                    if let n = try polynomials.degree(of: derivative, in: axis, using: &a), n > 0 {
                        let ac = try coefficientVector(remainder,axis:axis,&a)
                        let bc = try coefficientVector(derivative,axis:axis,&a)
                        for j in 0..<min(degree,n) {
                            let psc = try principal(firstCoefficients:ac,secondCoefficients:bc,index:j,&a)
                            try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                            witnesses.append(.principal(first: remainder, second: derivative, result: psc, axis: axis, index: j))
                            try insert(psc, into: &lower, &a)
                        }
                    }
                    try ExactCellAccess.storage(remainder.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
                    var terms: [ExactPolynomialTerm<Field.Value>] = []
                    for term in remainder.terms {
                        try a.consumeWork(1); if term.powers[axis] != degree { terms.append(term) }
                    }
                    remainder = try polynomials.polynomial(terms: terms, using: &a)
                }
                families.append(reducta)
            }
            for i in families.indices { for j in families.indices where j > i {
                for left in families[i] { for right in families[j] {
                    guard let m = try polynomials.degree(of: left, in: axis, using: &a), let n = try polynomials.degree(of: right, in: axis, using: &a) else { throw ExactRealCellFailure.invalidCoverage }
                    let ac = try coefficientVector(left,axis:axis,&a)
                    let bc = try coefficientVector(right,axis:axis,&a)
                    for k in 0..<min(m,n) {
                        let psc = try principal(firstCoefficients:ac,secondCoefficients:bc,index:k,&a)
                        try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                        witnesses.append(.principal(first:left,second:right,result:psc,axis:axis,index:k))
                        try insert(psc,into:&lower,&a)
                    }
                } }
            } }
            descending.append(.init(axis:axis,cutLawCount:cutLawCount,laws:laws,coefficients:coefficients,witnesses:witnesses)); pending = lower
        }
        try ExactCellAccess.storage(descending.count, ExactRealCellProjectionLevel<Base>.self, &a)
        return Array(descending.reversed())
    }
}
