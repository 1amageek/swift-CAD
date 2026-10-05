import CADCore

/// Exact lexicographic Buchberger basis for the complete original equation ideal.
struct ExactBivariateGroebnerBasis {
    private struct Pair { let first: Int; let second: Int }
    static func reducedBasis<B: RationalAlgebraAdmitting>(_ equations: [ExactBivariatePolynomial],
        usage: inout B) throws -> [ExactBivariatePolynomial] {
        var basis: [ExactBivariatePolynomial] = []
        for equation in equations where !equation.isZero {
            let value = try reduced(equation, by: basis, usage: &usage).normalized(usage: &usage)
            if !value.isZero { try usage.retainExactStorage(1); basis.append(value) }
        }
        var pending: [Pair] = []
        for i in basis.indices { for j in 0..<i {
            try usage.retainExactStorage(1); pending.append(Pair(first: j, second: i))
        } }
        while let pair = pending.popLast() {
            try Task.checkCancellation(); try usage.consumeExactWork(1)
            guard let a = basis[pair.first].leading, let b = basis[pair.second].leading else {
                throw rationalAlgebraFailure("Original Groebner pair lost its leading source coefficient.")
            }
            let u = max(a.key.u, b.key.u), v = max(a.key.v, b.key.v)
            let fa = try ExactBivariatePolynomial.monomial(u: u - a.key.u, v: v - a.key.v,
                coefficient: .one.divided(by: a.value, usage: &usage), usage: &usage)
            let fb = try ExactBivariatePolynomial.monomial(u: u - b.key.u, v: v - b.key.v,
                coefficient: .one.divided(by: b.value, usage: &usage), usage: &usage)
            let source = try basis[pair.first].multiplied(by: fa, usage: &usage)
                .subtracting(basis[pair.second].multiplied(by: fb, usage: &usage), usage: &usage)
            let value = try reduced(source, by: basis, usage: &usage).normalized(usage: &usage)
            if value.isZero { continue }
            if value.uDegree == 0, value.vDegree == 0 { return [value] }
            let index = basis.count
            for j in basis.indices { try usage.retainExactStorage(1); pending.append(Pair(first: j, second: index)) }
            try usage.retainExactStorage(1); basis.append(value)
        }
        // Select a minimal leading monomial set before reducing tails. Reducing
        // duplicate leaders against each other simultaneously could drop every
        // representative and lose the original leading ideal.
        var minimal: [ExactBivariatePolynomial] = []
        for i in basis.indices {
            guard let leading = basis[i].leading else { continue }
            var redundant = false
            for j in basis.indices where j != i {
                try usage.consumeExactWork(1)
                guard let other = basis[j].leading,
                      other.key.u <= leading.key.u, other.key.v <= leading.key.v else { continue }
                if other.key != leading.key || j < i { redundant = true; break }
            }
            if !redundant { try usage.retainExactStorage(1); minimal.append(basis[i]) }
        }
        var result: [ExactBivariatePolynomial] = []
        for i in minimal.indices {
            try usage.retainExactStorage(minimal.count)
            var others: [ExactBivariatePolynomial] = []
            for j in minimal.indices where j != i { others.append(minimal[j]) }
            let value = try reduced(minimal[i], by: others, usage: &usage).normalized(usage: &usage)
            guard let old = minimal[i].leading, let next = value.leading, old.key == next.key else {
                throw rationalAlgebraFailure("Minimal exact Groebner tail reduction lost an original leading monomial.")
            }
            try usage.retainExactStorage(1); result.append(value)
        }
        // Exact original generators must reduce to zero under the result.
        for equation in equations {
            guard try reduced(equation, by: result, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Reduced exact Groebner output does not preserve the original equation ideal.")
            }
        }
        return result
    }

    static func reduced<B: RationalAlgebraAdmitting>(_ source: ExactBivariatePolynomial,
        by basis: [ExactBivariatePolynomial], usage: inout B) throws -> ExactBivariatePolynomial {
        var pending = source, remainder = ExactBivariatePolynomial.zero
        while let lead = pending.leading {
            try usage.consumeExactWork(1)
            var canceled = false
            for divisor in basis {
                try usage.consumeExactWork(1)
                guard let d = divisor.leading, lead.key.u >= d.key.u, lead.key.v >= d.key.v else { continue }
                let term = try ExactBivariatePolynomial.monomial(u: lead.key.u - d.key.u, v: lead.key.v - d.key.v,
                    coefficient: lead.value.divided(by: d.value, usage: &usage), usage: &usage)
                pending = try pending.subtracting(divisor.multiplied(by: term, usage: &usage), usage: &usage)
                canceled = true; break
            }
            if !canceled {
                let term = try ExactBivariatePolynomial.monomial(u: lead.key.u, v: lead.key.v,
                    coefficient: lead.value, usage: &usage)
                remainder = try remainder.adding(term, usage: &usage)
                pending = try pending.subtracting(term, usage: &usage)
            }
            if let next = pending.leading {
                guard next.key.v < lead.key.v || next.key.v == lead.key.v && next.key.u < lead.key.u else {
                    throw rationalAlgebraFailure("Exact original Groebner reduction did not lower its leading source monomial.")
                }
            }
        }
        return remainder
    }
}
