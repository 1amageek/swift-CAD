/// Canonical univariate polynomial over one exact retained ordered field.
package struct OriginalSingularFieldPolynomial: Sendable {
    package let context: OriginalSingularFieldContext
    package let coefficients: [OriginalSingularFieldElement]
    package var degree: Int { coefficients.count - 1 }
    package var isZero: Bool { coefficients.isEmpty }

    package init<B: RationalAlgebraAdmitting>(context: OriginalSingularFieldContext,
        coefficients: [OriginalSingularFieldElement], maximumDepth: Int, usage: inout B) throws {
        self.context = context
        try RationalAlgebraStorage.retain(coefficients.count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(coefficients.count)
        for coefficient in coefficients {
            try usage.consumeExactWork(1)
            values.append(try coefficient.embedded(in: context, maximumDepth: maximumDepth, usage: &usage))
        }
        while let last = values.last {
            if case .zero = try last.sign(maximumDepth: maximumDepth, usage: &usage) { values.removeLast() }
            else { break }
        }
        self.coefficients = values
    }

    package func adding<B: RationalAlgebraAdmitting>(_ other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        try sameContext(other, usage: &usage)
        var values: [OriginalSingularFieldElement] = []
        let count = max(coefficients.count, other.coefficients.count)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        values.reserveCapacity(count)
        for i in 0..<count {
            let a = try coefficient(i, maximumDepth: maximumDepth, usage: &usage)
            let b = try other.coefficient(i, maximumDepth: maximumDepth, usage: &usage)
            values.append(try a.adding(b, maximumDepth: maximumDepth, usage: &usage))
        }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func negated<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> Self {
        var values: [OriginalSingularFieldElement] = []
        try RationalAlgebraStorage.retain(coefficients.count, of: OriginalSingularFieldElement.self, usage: &usage)
        values.reserveCapacity(coefficients.count)
        for value in coefficients { values.append(try value.negated(maximumDepth: maximumDepth, usage: &usage)) }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func subtracting<B: RationalAlgebraAdmitting>(_ other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        try adding(other.negated(maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
    }
    package func multiplied<B: RationalAlgebraAdmitting>(by other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        try sameContext(other, usage: &usage)
        if isZero || other.isZero { return try Self(context: context, coefficients: [], maximumDepth: maximumDepth, usage: &usage) }
        let count = try rationalAlgebraCount(coefficients.count, other.degree)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values = Array(repeating: zero, count: count)
        for i in coefficients.indices { for j in other.coefficients.indices {
            try usage.consumeExactWork(1)
            values[i + j] = try values[i + j].adding(coefficients[i].multiplied(by: other.coefficients[j],
                maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        } }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func differentiated<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> Self {
        var values: [OriginalSingularFieldElement] = []
        try RationalAlgebraStorage.retain(max(0, degree), of: OriginalSingularFieldElement.self, usage: &usage)
        values.reserveCapacity(max(0, degree))
        if degree > 0 { for i in 1...degree {
            let scale = try OriginalSingularFieldElement.constant(.natural(i, usage: &usage), in: context,
                maximumDepth: maximumDepth, usage: &usage)
            values.append(try coefficients[i].multiplied(by: scale, maximumDepth: maximumDepth, usage: &usage))
        } }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func evaluated<B: RationalAlgebraAdmitting>(at value: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        var descendant = value.context, target = context
        while true {
            try usage.consumeExactWork(1)
            if descendant === context { target = value.context; break }
            guard let parent = descendant.parent else { break }
            descendant = parent
        }
        let station = try value.embedded(in: target, maximumDepth: maximumDepth, usage: &usage)
        var result = try OriginalSingularFieldElement.constant(.zero, in: target, maximumDepth: maximumDepth, usage: &usage)
        for coefficient in coefficients.reversed() {
            try usage.consumeExactWork(1)
            result = try result.multiplied(by: station, maximumDepth: maximumDepth, usage: &usage)
                .adding(coefficient.embedded(in: target, maximumDepth: maximumDepth, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }
    package func divided<B: RationalAlgebraAdmitting>(by divisor: Self,
        maximumDepth: Int, usage: inout B) throws -> (quotient: Self, remainder: Self) {
        try sameContext(divisor, usage: &usage)
        guard let leading = divisor.coefficients.last else { throw rationalAlgebraFailure("Original tower polynomial divisor is zero.") }
        var remainder = self
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        let count = max(0, degree - divisor.degree + 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var quotient = Array(repeating: zero, count: count)
        while remainder.degree >= divisor.degree, let value = remainder.coefficients.last {
            try usage.consumeExactWork(1)
            let oldDegree = remainder.degree, shift = oldDegree - divisor.degree
            let ratio = try value.divided(by: leading, maximumDepth: maximumDepth, usage: &usage)
            quotient[shift] = ratio
            try RationalAlgebraStorage.retain(try rationalAlgebraCount(shift, 1), of: OriginalSingularFieldElement.self, usage: &usage)
            var term = Array(repeating: zero, count: shift); term.reserveCapacity(try rationalAlgebraCount(shift, 1)); term.append(ratio)
            let monomial = try Self(context: context, coefficients: term, maximumDepth: maximumDepth, usage: &usage)
            remainder = try remainder.subtracting(divisor.multiplied(by: monomial, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
            guard remainder.degree < oldDegree else { throw rationalAlgebraFailure("Original tower polynomial division did not lower degree.") }
        }
        return try (Self(context: context, coefficients: quotient, maximumDepth: maximumDepth, usage: &usage), remainder)
    }
    package static func gcd<B: RationalAlgebraAdmitting>(_ first: Self, _ second: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        var a = first, b = second
        while !b.isZero { let r = try a.divided(by: b, maximumDepth: maximumDepth, usage: &usage).remainder; a = b; b = r }
        return a
    }
    private func coefficient<B: RationalAlgebraAdmitting>(_ index: Int, maximumDepth: Int,
        usage: inout B) throws -> OriginalSingularFieldElement {
        if index < coefficients.count { return coefficients[index] }
        return try .constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
    }
    private func sameContext<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws {
        try usage.consumeExactWork(1)
        guard context === other.context else { throw rationalAlgebraFailure("Original tower polynomials need the identical immutable field owner.") }
    }
}
