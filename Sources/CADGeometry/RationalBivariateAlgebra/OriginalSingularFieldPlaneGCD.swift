/// Primitive original plane GCD over one retained exact ordered coefficient field.
struct OriginalSingularFieldPlaneGCD {
    static func gcd<B: ExactScalarAdmission & ~Copyable>(_ first: OriginalSingularFieldPlanePolynomial,
        _ second: OriginalSingularFieldPlanePolynomial, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPlanePolynomial {
        if first.isZero { return try second.normalized(maximumDepth: maximumDepth, usage: &usage) }
        if second.isZero { return try first.normalized(maximumDepth: maximumDepth, usage: &usage) }
        let c1 = try content(first, maximumDepth: maximumDepth, usage: &usage)
        let c2 = try content(second, maximumDepth: maximumDepth, usage: &usage)
        let common = try OriginalSingularFieldPolynomial.gcd(c1, c2, maximumDepth: maximumDepth, usage: &usage)
        var a = try primitive(first, content: c1, maximumDepth: maximumDepth, usage: &usage)
        var b = try primitive(second, content: c2, maximumDepth: maximumDepth, usage: &usage)
        if a.vDegree < b.vDegree { swap(&a, &b) }
        while !b.isZero {
            let remainder = try pseudoRemainder(a, b, maximumDepth: maximumDepth, usage: &usage)
            a = b
            if remainder.isZero { b = remainder }
            else { b = try primitive(remainder, content: content(remainder, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage) }
        }
        return try a.multiplied(by: plane(common, vPower: 0, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage).normalized(maximumDepth: maximumDepth, usage: &usage)
    }
    static func coefficient<B: ExactScalarAdmission & ~Copyable>(_ original: OriginalSingularFieldPlanePolynomial,
        vPower: Int, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial {
        let zero = try OriginalSingularFieldElement.constant(.zero, in: original.context, maximumDepth: maximumDepth, usage: &usage)
        let count = max(0, original.uDegree + 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values = Array(repeating: zero, count: count)
        for (power, value) in try original.orderedTerms(usage: &usage) where power.v == vPower { values[power.u] = value }
        return try .init(context: original.context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    static func plane<B: ExactScalarAdmission & ~Copyable>(_ source: OriginalSingularFieldPolynomial,
        vPower: Int, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPlanePolynomial {
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        try RationalAlgebraStorage.retain(source.coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        for (degree, value) in source.coefficients.enumerated() { values[try .init(u: degree, v: vPower)] = value }
        return try .init(context: source.context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    static func content<B: ExactScalarAdmission & ~Copyable>(_ original: OriginalSingularFieldPlanePolynomial,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial {
        var result = try OriginalSingularFieldPolynomial(context: original.context, coefficients: [], maximumDepth: maximumDepth, usage: &usage)
        if original.vDegree >= 0 { for degree in 0...original.vDegree {
            result = try OriginalSingularFieldPolynomial.gcd(result,
                coefficient(original, vPower: degree, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            if result.degree == 0 { break }
        } }
        return result
    }
    static func primitive<B: ExactScalarAdmission & ~Copyable>(_ original: OriginalSingularFieldPlanePolynomial,
        content: OriginalSingularFieldPolynomial, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPlanePolynomial {
        var result = try OriginalSingularFieldPlanePolynomial(context: original.context, coefficients: [:], maximumDepth: maximumDepth, usage: &usage)
        if original.vDegree >= 0 { for degree in 0...original.vDegree {
            let divided = try coefficient(original, vPower: degree, maximumDepth: maximumDepth, usage: &usage)
                .divided(by: content, maximumDepth: maximumDepth, usage: &usage)
            guard divided.remainder.isZero else { throw rationalAlgebraFailure("Original ordered-field content has a nonzero remainder.") }
            result = try result.adding(plane(divided.quotient, vPower: degree, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
        } }
        return result
    }
    private static func pseudoRemainder<B: ExactScalarAdmission & ~Copyable>(_ numerator: OriginalSingularFieldPlanePolynomial,
        _ divisor: OriginalSingularFieldPlanePolynomial, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPlanePolynomial {
        let divisorLead = try coefficient(divisor, vPower: divisor.vDegree, maximumDepth: maximumDepth, usage: &usage)
        var remainder = numerator
        while !remainder.isZero, remainder.vDegree >= divisor.vDegree {
            let degree = remainder.vDegree
            let value = try coefficient(remainder, vPower: degree, maximumDepth: maximumDepth, usage: &usage)
            let first = try remainder.multiplied(by: plane(divisorLead, vPower: 0, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
            let second = try divisor.multiplied(by: plane(value, vPower: degree - divisor.vDegree,
                maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            remainder = try first.subtracting(second, maximumDepth: maximumDepth, usage: &usage)
            guard remainder.isZero || remainder.vDegree < degree else { throw rationalAlgebraFailure("Original ordered-field PRS failed to lower its native degree.") }
        }
        return remainder
    }
}
