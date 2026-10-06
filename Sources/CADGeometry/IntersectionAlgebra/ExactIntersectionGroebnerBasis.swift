import CADCore

/// Exact Buchberger preparation with generator and S-pair verification.
enum ExactIntersectionGroebnerBasis {
    private struct Pair { let first: Int; let second: Int }

    static func reducedBasis<B: RationalAlgebraAdmitting>(_ equations: [ExactIntersectionPolynomial],
        variableCount: Int, usage: inout B) throws -> [ExactIntersectionPolynomial] {
        var basis: [ExactIntersectionPolynomial] = []
        for equation in equations {
            try intersectionAlgebraStep(&usage)
            let value = try reduced(equation, by: basis, usage: &usage).monic(usage: &usage)
            if value.isZero { continue }
            if value.isConstant { return try verified([value], equations: equations, usage: &usage) }
            try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
            basis.append(value)
        }
        var pending: [Pair] = []
        for i in basis.indices {
            for j in 0..<i {
                try intersectionAlgebraStep(&usage)
                try RationalAlgebraStorage.retain(1, of: Pair.self, usage: &usage)
                pending.append(Pair(first: j, second: i))
            }
        }
        while let pair = pending.popLast() {
            try intersectionAlgebraStep(&usage)
            let source = try sPolynomial(basis[pair.first], basis[pair.second], usage: &usage)
            let value = try reduced(source, by: basis, usage: &usage).monic(usage: &usage)
            if value.isZero { continue }
            if value.isConstant { return try verified([value], equations: equations, usage: &usage) }
            let index = basis.count
            for j in basis.indices {
                try intersectionAlgebraStep(&usage)
                try RationalAlgebraStorage.retain(1, of: Pair.self, usage: &usage)
                pending.append(Pair(first: j, second: index))
            }
            try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
            basis.append(value)
        }
        var minimal: [ExactIntersectionPolynomial] = []
        for i in basis.indices {
            guard let lead = try basis[i].leading(usage: &usage) else { continue }
            var redundant = false
            for j in basis.indices where i != j {
                try intersectionAlgebraStep(&usage)
                guard let other = try basis[j].leading(usage: &usage), other.power.divides(lead.power) else { continue }
                if other.power != lead.power || j < i { redundant = true; break }
            }
            if !redundant {
                try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
                minimal.append(basis[i])
            }
        }
        var result: [ExactIntersectionPolynomial] = []
        for i in minimal.indices {
            try RationalAlgebraStorage.retain(minimal.count - 1,
                of: ExactIntersectionPolynomial.self, usage: &usage)
            var others: [ExactIntersectionPolynomial] = []
            for j in minimal.indices where i != j {
                try intersectionAlgebraStep(&usage)
                others.append(minimal[j])
            }
            let value = try reduced(minimal[i], by: others, usage: &usage).monic(usage: &usage)
            guard try value.leading(usage: &usage)?.power == minimal[i].leading(usage: &usage)?.power else {
                throw rationalAlgebraFailure("Intersection tail reduction lost the original leading ideal.")
            }
            try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
            result.append(value)
        }
        try RationalAlgebraStorage.retain(result.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        try result.sort { left, right in
            guard let a = try left.leading(usage: &usage), let b = try right.leading(usage: &usage) else {
                throw rationalAlgebraFailure("A reduced intersection basis cannot contain a zero generator.")
            }
            return a.power.precedes(b.power)
        }
        return try verified(result, equations: equations, usage: &usage)
    }

    static func reduced<B: RationalAlgebraAdmitting>(_ source: ExactIntersectionPolynomial,
        by basis: [ExactIntersectionPolynomial], usage: inout B) throws -> ExactIntersectionPolynomial {
        var pending = source, remainder = try ExactIntersectionPolynomial.zero(variableCount: source.variableCount)
        while let lead = try pending.leading(usage: &usage) {
            try intersectionAlgebraStep(&usage)
            var canceled = false
            for divisor in basis {
                try intersectionAlgebraStep(&usage)
                guard let d = try divisor.leading(usage: &usage), d.power.divides(lead.power) else { continue }
                let power = try lead.power.quotient(by: d.power, variableCount: source.variableCount)
                let factor = try ExactIntersectionPolynomial.monomial(variableCount: source.variableCount,
                    powers: (power.a, power.b, power.c, power.d, power.e),
                    coefficient: lead.coefficient.divided(by: d.coefficient, usage: &usage), usage: &usage)
                pending = try pending.subtracting(divisor.multiplied(by: factor, usage: &usage), usage: &usage)
                canceled = true; break
            }
            if !canceled {
                let term = try ExactIntersectionPolynomial.monomial(variableCount: source.variableCount,
                    powers: (lead.power.a, lead.power.b, lead.power.c, lead.power.d, lead.power.e),
                    coefficient: lead.coefficient, usage: &usage)
                remainder = try remainder.adding(term, usage: &usage)
                pending = try pending.subtracting(term, usage: &usage)
            }
            if let next = try pending.leading(usage: &usage), !next.power.precedes(lead.power) {
                throw rationalAlgebraFailure("Intersection reduction failed strict lexicographic descent.")
            }
        }
        return remainder
    }

    private static func sPolynomial<B: RationalAlgebraAdmitting>(_ first: ExactIntersectionPolynomial,
        _ second: ExactIntersectionPolynomial, usage: inout B) throws -> ExactIntersectionPolynomial {
        guard let a = try first.leading(usage: &usage), let b = try second.leading(usage: &usage) else {
            throw rationalAlgebraFailure("Intersection S-pair requires two nonzero original generators.")
        }
        let lcm = try a.power.leastCommonMultiple(b.power, variableCount: first.variableCount)
        let ap = try lcm.quotient(by: a.power, variableCount: first.variableCount)
        let bp = try lcm.quotient(by: b.power, variableCount: first.variableCount)
        let af = try ExactIntersectionPolynomial.monomial(variableCount: first.variableCount,
            powers: (ap.a, ap.b, ap.c, ap.d, ap.e),
            coefficient: .one.divided(by: a.coefficient, usage: &usage), usage: &usage)
        let bf = try ExactIntersectionPolynomial.monomial(variableCount: first.variableCount,
            powers: (bp.a, bp.b, bp.c, bp.d, bp.e),
            coefficient: .one.divided(by: b.coefficient, usage: &usage), usage: &usage)
        return try first.multiplied(by: af, usage: &usage)
            .subtracting(second.multiplied(by: bf, usage: &usage), usage: &usage)
    }

    private static func verified<B: RationalAlgebraAdmitting>(_ basis: [ExactIntersectionPolynomial],
        equations: [ExactIntersectionPolynomial], usage: inout B) throws -> [ExactIntersectionPolynomial] {
        for equation in equations {
            guard try reduced(equation, by: basis, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Prepared intersection ideal lost an original equation.")
            }
        }
        for i in basis.indices {
            for j in 0..<i {
                let pair = try sPolynomial(basis[j], basis[i], usage: &usage)
                guard try reduced(pair, by: basis, usage: &usage).isZero else {
                    throw rationalAlgebraFailure("Prepared intersection ideal has an unresolved S-pair.")
                }
            }
        }
        return basis
    }
}
