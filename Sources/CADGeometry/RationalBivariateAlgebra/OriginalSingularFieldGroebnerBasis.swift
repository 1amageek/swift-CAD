import CADCore

/// Exact lexicographic source ideal over a retained singular-resolution ordered field.
struct OriginalSingularFieldGroebnerBasis {
    private struct Pair { let first: Int; let second: Int }
    static func reducedBasis<B: RationalAlgebraAdmitting>(_ equations: [OriginalSingularFieldPlanePolynomial],
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldPlanePolynomial] {
        var basis: [OriginalSingularFieldPlanePolynomial] = []
        for equation in equations where !equation.isZero {
            let value = try reduced(equation, by: basis, maximumDepth: maximumDepth, usage: &usage).normalized(maximumDepth: maximumDepth, usage: &usage)
            if !value.isZero { try usage.retainExactStorage(1); basis.append(value) }
        }
        var pending: [Pair] = []
        for i in basis.indices { for j in 0..<i {
            try usage.retainExactStorage(1); pending.append(Pair(first: j, second: i))
        } }
        while let pair = pending.popLast() {
            try Task.checkCancellation(); try usage.consumeExactWork(1)
            guard let a = try basis[pair.first].leading(usage: &usage), let b = try basis[pair.second].leading(usage: &usage) else {
                throw rationalAlgebraFailure("Original Groebner pair lost its leading source coefficient.")
            }
            let u = max(a.key.u, b.key.u), v = max(a.key.v, b.key.v)
            let fa = try OriginalSingularFieldPlanePolynomial.monomial(u: u - a.key.u, v: v - a.key.v,
                coefficient: OriginalSingularFieldElement.constant(.one, in: a.value.context, maximumDepth: maximumDepth, usage: &usage).divided(by: a.value, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            let fb = try OriginalSingularFieldPlanePolynomial.monomial(u: u - b.key.u, v: v - b.key.v,
                coefficient: OriginalSingularFieldElement.constant(.one, in: b.value.context, maximumDepth: maximumDepth, usage: &usage).divided(by: b.value, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            let source = try basis[pair.first].multiplied(by: fa, maximumDepth: maximumDepth, usage: &usage)
                .subtracting(basis[pair.second].multiplied(by: fb, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            let value = try reduced(source, by: basis, maximumDepth: maximumDepth, usage: &usage).normalized(maximumDepth: maximumDepth, usage: &usage)
            if value.isZero { continue }
            if value.uDegree == 0, value.vDegree == 0 { return [value] }
            let index = basis.count
            for j in basis.indices { try usage.retainExactStorage(1); pending.append(Pair(first: j, second: index)) }
            try usage.retainExactStorage(1); basis.append(value)
        }
        // Select a minimal leading monomial set before reducing tails. Reducing
        // duplicate leaders against each other simultaneously could drop every
        // representative and lose the original leading ideal.
        var minimal: [OriginalSingularFieldPlanePolynomial] = []
        for i in basis.indices {
            guard let leading = try basis[i].leading(usage: &usage) else { continue }
            var redundant = false
            for j in basis.indices where j != i {
                try usage.consumeExactWork(1)
                guard let other = try basis[j].leading(usage: &usage),
                      other.key.u <= leading.key.u, other.key.v <= leading.key.v else { continue }
                if other.key != leading.key || j < i { redundant = true; break }
            }
            if !redundant { try usage.retainExactStorage(1); minimal.append(basis[i]) }
        }
        var result: [OriginalSingularFieldPlanePolynomial] = []
        for i in minimal.indices {
            try usage.retainExactStorage(minimal.count)
            var others: [OriginalSingularFieldPlanePolynomial] = []
            for j in minimal.indices where j != i { others.append(minimal[j]) }
            let value = try reduced(minimal[i], by: others, maximumDepth: maximumDepth, usage: &usage).normalized(maximumDepth: maximumDepth, usage: &usage)
            guard let old = try minimal[i].leading(usage: &usage), let next = try value.leading(usage: &usage), old.key == next.key else {
                throw rationalAlgebraFailure("Minimal exact Groebner tail reduction lost an original leading monomial.")
            }
            try usage.retainExactStorage(1); result.append(value)
        }
        // Exact original generators must reduce to zero under the result.
        for equation in equations {
            guard try reduced(equation, by: result, maximumDepth: maximumDepth, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Reduced exact Groebner output does not preserve the original equation ideal.")
            }
        }
        return result
    }

    static func reduced<B: RationalAlgebraAdmitting>(_ source: OriginalSingularFieldPlanePolynomial,
        by basis: [OriginalSingularFieldPlanePolynomial], maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPlanePolynomial {
        var pending = source
        var remainder = try OriginalSingularFieldPlanePolynomial(context: source.context, coefficients: [:], maximumDepth: maximumDepth, usage: &usage)
        while let lead = try pending.leading(usage: &usage) {
            try usage.consumeExactWork(1)
            var canceled = false
            for divisor in basis {
                try usage.consumeExactWork(1)
                guard let d = try divisor.leading(usage: &usage), lead.key.u >= d.key.u, lead.key.v >= d.key.v else { continue }
                let term = try OriginalSingularFieldPlanePolynomial.monomial(u: lead.key.u - d.key.u, v: lead.key.v - d.key.v,
                    coefficient: lead.value.divided(by: d.value, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
                pending = try pending.subtracting(divisor.multiplied(by: term, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
                canceled = true; break
            }
            if !canceled {
                let term = try OriginalSingularFieldPlanePolynomial.monomial(u: lead.key.u, v: lead.key.v,
                    coefficient: lead.value, maximumDepth: maximumDepth, usage: &usage)
                remainder = try remainder.adding(term, maximumDepth: maximumDepth, usage: &usage)
                pending = try pending.subtracting(term, maximumDepth: maximumDepth, usage: &usage)
            }
            if let next = try pending.leading(usage: &usage) {
                guard next.key.v < lead.key.v || next.key.v == lead.key.v && next.key.u < lead.key.u else {
                    throw rationalAlgebraFailure("Exact original Groebner reduction did not lower its leading source monomial.")
                }
            }
        }
        return remainder
    }
}
