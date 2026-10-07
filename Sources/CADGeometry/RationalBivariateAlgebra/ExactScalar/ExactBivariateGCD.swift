/// Primitive pseudo-remainder GCD in Q[u][v], without rounded division.
public struct ExactBivariateGCD: ExactBivariateGCDProducing, Sendable {
    public init() {}

    public func greatestCommonDivisor<B: RationalAlgebraAdmitting>(
        _ first: ExactBivariatePolynomial, _ second: ExactBivariatePolynomial,
        usage: inout B) throws -> ExactBivariatePolynomial {
        if first.isZero { return try second.normalized(usage: &usage) }
        if second.isZero { return try first.normalized(usage: &usage) }
        let firstContent = try content(first, usage: &usage)
        let secondContent = try content(second, usage: &usage)
        let sharedContent = try univariateGCD(firstContent, secondContent, usage: &usage)
        var a = try divideCoefficients(first, by: firstContent, usage: &usage)
        var b = try divideCoefficients(second, by: secondContent, usage: &usage)
        if a.vDegree < b.vDegree { swap(&a, &b) }
        while !b.isZero {
            try exactScalarTaskCheckpoint()
            let remainder = try pseudoRemainder(a, b, usage: &usage)
            a = b
            if remainder.isZero { b = .zero }
            else { b = try divideCoefficients(remainder, by: content(remainder, usage: &usage), usage: &usage) }
        }
        return try a.multiplied(by: sharedContent, usage: &usage).normalized(usage: &usage)
    }

    func univariateDivision<B: RationalAlgebraAdmitting>(_ numerator: ExactBivariatePolynomial,
        _ divisor: ExactBivariatePolynomial, usage: inout B)
        throws -> (quotient: ExactBivariatePolynomial, remainder: ExactBivariatePolynomial) {
        guard numerator.vDegree <= 0, divisor.vDegree == 0, !divisor.isZero else {
            throw exactScalarBackendFailure("Univariate exact division requires a nonzero Q[u] divisor.")
        }
        var remainder = numerator, quotient = ExactBivariatePolynomial.zero
        guard let divisorLead = divisor.leading else { throw exactScalarBackendFailure("Missing exact divisor coefficient.") }
        while let lead = remainder.leading, lead.key.u >= divisorLead.key.u {
            try usage.consumeExactWork(1)
            try RationalAlgebraStorage.retain(1,
                of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
            let power = try ExactBivariatePolynomial.Power(u: lead.key.u - divisorLead.key.u, v: 0)
            let ratio = try lead.value.divided(by: divisorLead.value, usage: &usage)
            let term = ExactBivariatePolynomial([power: ratio])
            quotient = try quotient.adding(term, usage: &usage)
            let next = try remainder.subtracting(divisor.multiplied(by: term, usage: &usage), usage: &usage)
            guard next.isZero || next.uDegree < remainder.uDegree else {
                throw exactScalarBackendFailure("Exact univariate division failed to reduce its degree.")
            }
            remainder = next
        }
        return (quotient, remainder)
    }

    func univariateGCD<B: RationalAlgebraAdmitting>(_ first: ExactBivariatePolynomial,
        _ second: ExactBivariatePolynomial, usage: inout B) throws -> ExactBivariatePolynomial {
        var a = first, b = second
        while !b.isZero {
            let remainder = try univariateDivision(a, b, usage: &usage).remainder
            a = b; b = remainder
        }
        return try a.normalized(usage: &usage)
    }

    func content<B: RationalAlgebraAdmitting>(_ source: ExactBivariatePolynomial,
        usage: inout B) throws -> ExactBivariatePolynomial {
        if source.isZero { return .zero }
        var result = ExactBivariatePolynomial.zero
        for degree in 0...source.vDegree {
            let coefficient = try source.coefficient(ofV: degree, usage: &usage)
            result = try univariateGCD(result, coefficient, usage: &usage)
            if result.uDegree == 0 { break }
        }
        return result
    }

    func divideCoefficients<B: RationalAlgebraAdmitting>(_ source: ExactBivariatePolynomial,
        by divisor: ExactBivariatePolynomial, usage: inout B) throws -> ExactBivariatePolynomial {
        if source.isZero { return .zero }
        var result = ExactBivariatePolynomial.zero
        for degree in 0...source.vDegree {
            let division = try univariateDivision(source.coefficient(ofV: degree, usage: &usage), divisor, usage: &usage)
            guard division.remainder.isZero else {
                throw exactScalarBackendFailure("Exact polynomial content does not divide its original coefficient.")
            }
            result = try result.adding(division.quotient.shiftedV(degree, usage: &usage), usage: &usage)
        }
        return result
    }

    func pseudoRemainder<B: RationalAlgebraAdmitting>(_ numerator: ExactBivariatePolynomial,
        _ divisor: ExactBivariatePolynomial, usage: inout B) throws -> ExactBivariatePolynomial {
        guard !divisor.isZero else { throw exactScalarBackendFailure("Exact pseudo-remainder division by zero.") }
        let divisorDegree = divisor.vDegree
        let divisorLead = try divisor.coefficient(ofV: divisorDegree, usage: &usage)
        var remainder = numerator
        while !remainder.isZero, remainder.vDegree >= divisorDegree {
            let degree = remainder.vDegree
            let lead = try remainder.coefficient(ofV: degree, usage: &usage)
            let a = try remainder.multiplied(by: divisorLead, usage: &usage)
            let b = try divisor.multiplied(by: lead, usage: &usage).shiftedV(degree - divisorDegree, usage: &usage)
            let next = try a.subtracting(b, usage: &usage)
            guard next.isZero || next.vDegree < degree else {
                throw exactScalarBackendFailure("Exact primitive pseudo-remainder failed to reduce its degree.")
            }
            remainder = next
        }
        return remainder
    }
}
