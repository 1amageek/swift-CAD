#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain: ExactPolynomialSubresultantProducing {
    public typealias Subresultants = ExactPrincipalSubresultantSequence<F>
    public func principalSubresultants<A: ExactScalarAdmission & ~Copyable>(
        _ first: borrowing Polynomial, _ second: borrowing Polynomial, eliminating variable: Int,
        using admission: inout A) throws(ExactPolynomialFailure) -> Subresultants {
        try principalSubresultants(first, second, eliminating: variable, algorithm: .automatic, using: &admission)
    }
    func principalSubresultants<A: ExactScalarAdmission & ~Copyable>(
        _ first: borrowing Polynomial, _ second: borrowing Polynomial, eliminating variable: Int,
        algorithm: ExactPolynomialSubresultantAlgorithm, using admission: inout A
    ) throws(ExactPolynomialFailure) -> Subresultants {
        try query(&admission, copy first, copy second) { usage in
            try requireVariable(variable)
            let m = try degree(first, variable, &usage), n = try degree(second, variable, &usage)
            let count = min(m ?? 0, n ?? 0)
            try ExactPolynomialAccess.storage(count, Polynomial.self, &usage)
            var values = Array(repeating: try wrap([], &usage), count: count)
            if count > 0, let m, let n {
                // Select before algorithm work; failures never trigger a second computation.
                let selected: ExactPolynomialSubresultantAlgorithm = algorithm == .automatic
                    ? (max(m,n) <= 1 ? .determinant : .prs) : algorithm
                if selected == .determinant {
                    if m == 1 && n == 1 {
                        let a1 = try axisCoefficient(first, variable: variable, degree: 1, &usage)
                        let a0 = try axisCoefficient(first, variable: variable, degree: 0, &usage)
                        let b1 = try axisCoefficient(second, variable: variable, degree: 1, &usage)
                        let b0 = try axisCoefficient(second, variable: variable, degree: 0, &usage)
                        values[0] = try subtracting(multiplying(a1, b0, &usage), multiplying(a0, b1, &usage), &usage)
                    } else {
                        let ac = try coefficients(first, variable, &usage), bc = try coefficients(second, variable, &usage)
                        for index in values.indices {
                            try usage.consumeWork(1)
                            values[index] = try principalDeterminant(ac, bc, m: m, n: n, index: index, &usage)
                        }
                    }
                } else {
                    try principalPRS(first, second, m: m, n: n, variable: variable, values: &values, &usage)
                }
            }
            // Zero entries from degree defects retain the proof depth of the entire sequence.
            for index in values.indices {
                try usage.consumeWork(1)
                for term in values[index].terms {
                    try usage.consumeWork(1)
                    guard term.powers[variable] == 0 else { throw ExactPolynomialFailure.invalidCertificate }
                }
                values[index] = try wrap(values[index].terms, &usage)
            }
            return Subresultants(first: copy first, second: copy second, variable: variable,
                values: values, depth: try usage.depth)
        }
    }
    func axisCoefficient<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        variable: Int, degree: Int, _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        var count = 0
        for term in value.terms {
            try usage.consumeWork(1)
            if term.powers[variable] == degree { count = try ExactPolynomialAccess.count(count, 1) }
        }
        try ExactPolynomialAccess.storage(count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(count)
        for term in value.terms {
            try usage.consumeWork(try ExactPolynomialAccess.count(variableCount, 1))
            if term.powers[variable] != degree { continue }
            try ExactPolynomialAccess.storage(variableCount, Int.self, &usage)
            var exponent = term.powers; exponent[variable] = 0
            terms.append(.init(powers: exponent, coefficient: term.coefficient))
        }
        // A fixed-degree slice retains canonical order and distinct remaining exponents.
        return try wrap(terms, &usage)
    }
    func subresultantRemainder<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing Polynomial,
        _ second: borrowing Polynomial, variable: Int, _ usage: inout ExactPolynomialAdmission<A>
    ) throws -> Polynomial {
        guard let n = try degree(second, variable, &usage) else { throw ExactPolynomialFailure.zeroDivisor }
        guard let m = try degree(first, variable, &usage) else { return try wrap([], &usage) }
        if m < n { return copy first }
        let leading = try axisCoefficient(second, variable: variable, degree: n, &usage)
        var remaining = try ExactPolynomialAccess.count(m - n, 1), remainder = copy first
        while let degree = try self.degree(remainder, variable, &usage), degree >= n {
            try usage.consumeWork(1)
            let coefficient = try axisCoefficient(remainder, variable: variable, degree: degree, &usage)
            let next = try subtracting(multiplying(remainder, leading, &usage),
                shifted(multiplying(second, coefficient, &usage), variable, degree - n, &usage), &usage)
            if let following = try self.degree(next, variable, &usage), following >= degree {
                throw ExactPolynomialFailure.invalidCertificate
            }
            remaining -= 1; remainder = next
        }
        if remaining > 0 && !remainder.terms.isEmpty {
            remainder = try multiplying(remainder, power(leading, remaining, &usage), &usage)
        }
        return try wrap(remainder.terms, &usage)
    }
    func principalPRS<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing Polynomial,
        _ second: borrowing Polynomial, m: Int, n: Int, variable: Int,
        values: inout [Polynomial], _ usage: inout ExactPolynomialAdmission<A>) throws {
        let swapped = m < n
        let f = swapped ? copy second : copy first
        var g = swapped ? copy first : copy second
        var previousDegree = min(m,n)
        let initialDrop = max(m,n) - previousDegree
        var h = try subresultantRemainder(f, g, variable: variable, &usage)
        if initialDrop % 2 == 0 { h = try negated(h, &usage) }
        var lc = try axisCoefficient(g, variable: variable, degree: previousDegree, &usage)
        var c = try negated(power(lc, initialDrop, &usage), &usage)
        while let k = try degree(h, variable, &usage) {
            try usage.consumeWork(1)
            guard k < previousDegree, k < values.count else { throw ExactPolynomialFailure.invalidCertificate }
            let drop = previousDegree - k
            let nextLC = try axisCoefficient(h, variable: variable, degree: k, &usage)
            let nextC = try drop > 1
                ? exactDivide(power(negated(nextLC, &usage), drop, &usage), power(c, drop - 1, &usage), &usage)
                : negated(nextLC, &usage)
            values[k] = try negated(nextC, &usage)
            if k == 0 { break }
            let divisor = try negated(multiplying(lc, power(c, drop, &usage), &usage), &usage)
            let next = try exactDivide(subresultantRemainder(g, h, variable: variable, &usage), divisor, &usage)
            g = h; h = next; lc = nextLC; c = nextC; previousDegree = k
        }
        if swapped {
            for index in values.indices {
                try usage.consumeWork(1)
                if (m - index) % 2 == 1 && (n - index) % 2 == 1 {
                    values[index] = try negated(values[index], &usage)
                }
            }
        }
    }
}
