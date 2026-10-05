/// Original polynomial in v with exact algebraic coefficients at a source u-root.
struct ExactAlgebraicFiberPolynomial: Sendable {
    let root: ExactAlgebraicRealRoot
    let coefficients: [Int: ExactAlgebraicFieldElement]
    var degree: Int { coefficients.keys.max() ?? -1 }
    var isZero: Bool { coefficients.isEmpty }
    init<B: RationalAlgebraAdmitting>(source: ExactBivariatePolynomial,
        at root: ExactAlgebraicRealRoot, maximumDepth: Int, usage: inout B) throws {
        self.root = root
        var values: [Int: ExactAlgebraicFieldElement] = [:]
        if !source.isZero { for degree in 0...source.vDegree {
            let polynomial = try source.coefficient(ofV: degree, usage: &usage)
            let value = try ExactAlgebraicFieldElement(polynomial: polynomial, usage: &usage)
            if case .zero = try value.sign(at: root, maximumDepth: maximumDepth, usage: &usage) { continue }
            try usage.retainExactStorage(1); values[degree] = value
        } }
        coefficients = values
    }
    init(root: ExactAlgebraicRealRoot, coefficients: [Int: ExactAlgebraicFieldElement]) {
        self.root = root; self.coefficients = coefficients
    }
    func differentiated<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Self {
        var values: [Int: ExactAlgebraicFieldElement] = [:]
        for degree in try orderedDegrees(usage: &usage) where degree > 0 {
            guard let coefficient = coefficients[degree] else { throw rationalAlgebraFailure("Missing original fiber coefficient.") }
            let scalar = try ExactBivariatePolynomial.constant(.natural(degree, usage: &usage), usage: &usage)
            let multiplier = try ExactAlgebraicFieldElement(polynomial: scalar, usage: &usage)
            try usage.retainExactStorage(1); values[degree - 1] = try coefficient.multiplied(by: multiplier, usage: &usage)
        }
        return Self(root: root, coefficients: values)
    }
    func evaluated<B: RationalAlgebraAdmitting>(at station: ExactRationalCoefficient,
        usage: inout B) throws -> ExactAlgebraicFieldElement {
        var result = try ExactAlgebraicFieldElement(polynomial: .zero, usage: &usage)
        let factor = try ExactAlgebraicFieldElement(polynomial: .constant(station, usage: &usage), usage: &usage)
        if degree >= 0 { for index in (0...degree).reversed() {
            try usage.consumeExactWork(1)
            result = try result.multiplied(by: factor, usage: &usage)
            if let coefficient = coefficients[index] { result = try result.adding(coefficient, usage: &usage) }
        } }
        return result
    }
    func divided<B: RationalAlgebraAdmitting>(by divisor: Self,
        maximumDepth: Int, usage: inout B) throws -> (quotient: Self, remainder: Self) {
        try requireSameRootAuthority(divisor, usage: &usage)
        guard let leading = divisor.coefficients[divisor.degree] else {
            throw rationalAlgebraFailure("Exact algebraic fiber division by zero.")
        }
        var pending = coefficients, quotient: [Int: ExactAlgebraicFieldElement] = [:]
        while let degree = pending.keys.max(), degree >= divisor.degree {
            guard let value = pending[degree] else { throw rationalAlgebraFailure("Missing source fiber leading coefficient.") }
            let shift = degree - divisor.degree
            let ratio = try value.divided(by: leading, at: root, maximumDepth: maximumDepth, usage: &usage)
            try usage.retainExactStorage(1); quotient[shift] = ratio
            for index in try divisor.orderedDegrees(usage: &usage) {
                guard let coefficient = divisor.coefficients[index] else { throw rationalAlgebraFailure("Missing exact fiber divisor coefficient.") }
                let target = try rationalAlgebraCount(index, shift)
                let product = try coefficient.multiplied(by: ratio, usage: &usage)
                let old = try pending[target] ?? ExactAlgebraicFieldElement(polynomial: .zero, usage: &usage)
                let next = try old.subtracting(product, usage: &usage)
                if case .zero = try next.sign(at: root, maximumDepth: maximumDepth, usage: &usage) {
                    pending.removeValue(forKey: target)
                } else {
                    if pending[target] == nil { try usage.retainExactStorage(1) }; pending[target] = next
                }
            }
            guard (pending.keys.max() ?? -1) < degree else {
                throw rationalAlgebraFailure("Exact algebraic fiber division did not lower its source degree.")
            }
        }
        return (Self(root: root, coefficients: quotient), Self(root: root, coefficients: pending))
    }
    func negated<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Self {
        try usage.retainExactStorage(coefficients.count)
        var values: [Int: ExactAlgebraicFieldElement] = [:]
        for (degree, value) in coefficients { values[degree] = try value.negated(usage: &usage) }
        return Self(root: root, coefficients: values)
    }
    static func gcd<B: RationalAlgebraAdmitting>(_ first: Self, _ second: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try first.requireSameRootAuthority(second, usage: &usage)
        var a = first, b = second
        while !b.isZero {
            let remainder = try a.divided(by: b, maximumDepth: maximumDepth, usage: &usage).remainder
            a = b; b = remainder
        }
        return a
    }
    private func orderedDegrees<B: RationalAlgebraAdmitting>(usage: inout B) throws -> [Int] {
        let count = coefficients.count
        try usage.consumeExactWork(try rationalAlgebraCount(count, max(1, count), multiply: true))
        try usage.retainExactStorage(count)
        return coefficients.keys.sorted()
    }
    private func requireSameRootAuthority<B: RationalAlgebraAdmitting>(_ other: Self,
        usage: inout B) throws {
        try usage.consumeExactWork(try rationalAlgebraCount(root.polynomial.coefficients.count,
            other.root.polynomial.coefficients.count))
        let first = root.isolation, second = other.root.isolation
        guard root.polynomial == other.root.polynomial, first.lower == second.lower,
              first.upper == second.upper, first.excludesLowerEndpoint == second.excludesLowerEndpoint,
              first.excludesUpperEndpoint == second.excludesUpperEndpoint else {
            throw rationalAlgebraFailure("Ordered-field polynomial operations require the same original projection root authority.")
        }
    }

}
