/// Exact local plane polynomial over the original station's algebraic tower.
package struct OriginalSingularFieldPlanePolynomial: Sendable {
    package let context: OriginalSingularFieldContext
    package let coefficients: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement]
    package var isZero: Bool { coefficients.isEmpty }
    package func minimumOrder<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> Int? {
        var result: Int?
        for (power, _) in try orderedTerms(usage: &usage) {
            let order = try rationalAlgebraCount(power.u, power.v)
            result = min(result ?? order, order)
        }
        return result
    }
    func orderedTerms<B: ExactScalarAdmission & ~Copyable>(usage: inout B)
        throws -> [(key: ExactBivariatePolynomial.Power, value: OriginalSingularFieldElement)] {
        let count = coefficients.count
        try usage.consumeWork(try rationalAlgebraCount(count, max(1, count), multiply: true))
        try RationalAlgebraStorage.retain(count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        return coefficients.sorted { a, b in a.key.u == b.key.u ? a.key.v < b.key.v : a.key.u < b.key.u }
    }

    package init<B: ExactScalarAdmission & ~Copyable>(context: OriginalSingularFieldContext,
        coefficients: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement],
        maximumDepth: Int, usage: inout B) throws {
        self.context = context
        try RationalAlgebraStorage.retain(coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        try usage.consumeWork(try rationalAlgebraCount(coefficients.count, max(1, coefficients.count), multiply: true))
        try RationalAlgebraStorage.retain(coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        for (power, coefficient) in coefficients.sorted(by: { a, b in a.key.u == b.key.u ? a.key.v < b.key.v : a.key.u < b.key.u }) {
            let value = try coefficient.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
            if case .zero = try value.sign(maximumDepth: maximumDepth, usage: &usage) { continue }
            values[power] = value
        }
        self.coefficients = values
    }

    package static func translated<B: ExactScalarAdmission & ~Copyable>(_ original: ExactBivariatePolynomial,
        at root: ExactBivariateSystemRoot, maximumDepth: Int, usage: inout B) throws -> Self {
        guard case .zero = try root.sign(of: original, maximumDepth: maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original singular translation requires its retained source zero.")
        }
        let context = try OriginalSingularFieldContext(original: root, usage: &usage)
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        var uDerivative = original
        var uFactorial = ExactRationalCoefficient.one
        if original.uDegree >= 0, original.vDegree >= 0 { for u in 0...original.uDegree {
            var derivative = uDerivative, vFactorial = ExactRationalCoefficient.one
            for v in 0...original.vDegree {
                let divisor = try uFactorial.multiplied(by: vFactorial, usage: &usage)
                let coefficient = try OriginalSingularFieldElement.original(derivative, in: context, usage: &usage)
                    .divided(by: .constant(divisor, in: context, maximumDepth: maximumDepth, usage: &usage),
                        maximumDepth: maximumDepth, usage: &usage)
                if case .zero = try coefficient.sign(maximumDepth: maximumDepth, usage: &usage) {} else {
                    try RationalAlgebraStorage.retain(1,
                        of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
                    values[try .init(u: u, v: v)] = coefficient
                }
                derivative = try derivative.differentiated(alongU: false, usage: &usage)
                vFactorial = try vFactorial.multiplied(by: .natural(v + 1, usage: &usage), usage: &usage)
            }
            uDerivative = try uDerivative.differentiated(alongU: true, usage: &usage)
            uFactorial = try uFactorial.multiplied(by: .natural(u + 1, usage: &usage), usage: &usage)
        } }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }

    package static func coordinate<B: ExactScalarAdmission & ~Copyable>(alongU: Bool, in context: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> Self {
        return try Self(context: context, coefficients: [.init(u: alongU ? 1 : 0, v: alongU ? 0 : 1):
            .constant(.one, in: context, maximumDepth: maximumDepth, usage: &usage)], maximumDepth: maximumDepth, usage: &usage)
    }
    package static func constant<B: ExactScalarAdmission & ~Copyable>(_ coefficient: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try Self(context: coefficient.context, coefficients: [.init(u: 0, v: 0): coefficient], maximumDepth: maximumDepth, usage: &usage)
    }
    package func embedded<B: ExactScalarAdmission & ~Copyable>(in target: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try Self(context: target, coefficients: coefficients, maximumDepth: maximumDepth, usage: &usage)
    }
    package func adding<B: ExactScalarAdmission & ~Copyable>(_ other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        guard context === other.context else { throw rationalAlgebraFailure("Local original plane sum has unrelated field owners.") }
        try RationalAlgebraStorage.retain(rationalAlgebraCount(coefficients.count, other.coefficients.count),
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        var result = coefficients
        for (power, coefficient) in try other.orderedTerms(usage: &usage) {
            try usage.consumeWork(1)
            let old = try result[power] ?? OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
            result[power] = try old.adding(coefficient, maximumDepth: maximumDepth, usage: &usage)
        }
        return try Self(context: context, coefficients: result, maximumDepth: maximumDepth, usage: &usage)
    }
    package func multiplied<B: ExactScalarAdmission & ~Copyable>(by other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        guard context === other.context else { throw rationalAlgebraFailure("Local original plane product has unrelated field owners.") }
        var result: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        for (a, first) in try orderedTerms(usage: &usage) { for (b, second) in try other.orderedTerms(usage: &usage) {
            try usage.consumeWork(1)
            let target = try ExactBivariatePolynomial.Power(u: rationalAlgebraCount(a.u, b.u), v: rationalAlgebraCount(a.v, b.v))
            let product = try first.multiplied(by: second, maximumDepth: maximumDepth, usage: &usage)
            if let old = result[target] { result[target] = try old.adding(product, maximumDepth: maximumDepth, usage: &usage) }
            else {
                try RationalAlgebraStorage.retain(1,
                    of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
                result[target] = product
            }
        } }
        return try Self(context: context, coefficients: result, maximumDepth: maximumDepth, usage: &usage)
    }
    package func composed<B: ExactScalarAdmission & ~Copyable>(withU u: Self, v: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        guard context === u.context, context === v.context else { throw rationalAlgebraFailure("Original strict-transform composition has unrelated field owners.") }
        var result = try Self(context: context, coefficients: [:], maximumDepth: maximumDepth, usage: &usage)
        for (power, coefficient) in try orderedTerms(usage: &usage) {
            var term = try Self.constant(coefficient, maximumDepth: maximumDepth, usage: &usage)
            for _ in 0..<power.u { term = try term.multiplied(by: u, maximumDepth: maximumDepth, usage: &usage) }
            for _ in 0..<power.v { term = try term.multiplied(by: v, maximumDepth: maximumDepth, usage: &usage) }
            result = try result.adding(term, maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }
    package func tangentPolynomial<B: ExactScalarAdmission & ~Copyable>(alongU: Bool, maximumDepth: Int,
        usage: inout B) throws -> OriginalSingularFieldPolynomial {
        guard let order = try minimumOrder(usage: &usage) else { throw rationalAlgebraFailure("Original local tangent has a zero source law.") }
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(rationalAlgebraCount(order, 1),
            of: OriginalSingularFieldElement.self, usage: &usage)
        var values = Array(repeating: zero, count: order + 1)
        for (power, coefficient) in try orderedTerms(usage: &usage) where try rationalAlgebraCount(power.u, power.v) == order {
            values[alongU ? power.v : power.u] = coefficient
        }
        return try OriginalSingularFieldPolynomial(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func removingExceptionalPower<B: ExactScalarAdmission & ~Copyable>(alongU: Bool,
        maximumDepth: Int, usage: inout B) throws -> (polynomial: Self, power: Int) {
        let terms = try orderedTerms(usage: &usage)
        var minimum: Int?
        for (power, _) in terms { try usage.consumeWork(1); let value = alongU ? power.u : power.v; minimum = min(minimum ?? value, value) }
        guard let order = minimum else { throw rationalAlgebraFailure("Original strict transform vanished identically.") }
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        try RationalAlgebraStorage.retain(coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        for (power, value) in terms {
            values[try .init(u: power.u - (alongU ? order : 0), v: power.v - (alongU ? 0 : order))] = value
        }
        return try (Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage), order)
    }
}
