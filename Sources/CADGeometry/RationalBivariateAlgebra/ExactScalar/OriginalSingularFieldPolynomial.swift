/// Canonical univariate polynomial over one exact retained ordered field.
package struct OriginalSingularFieldPolynomial: Sendable {
    package let context: OriginalSingularFieldContext
    package let coefficients: [OriginalSingularFieldElement]
    package var degree: Int { coefficients.count - 1 }
    package var isZero: Bool { coefficients.isEmpty }

    package init<B: ExactScalarAdmission & ~Copyable>(context: OriginalSingularFieldContext,
        coefficients: [OriginalSingularFieldElement], maximumDepth: Int, usage: inout B) throws {
        self.context = context
        try RationalAlgebraStorage.retain(coefficients.count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(coefficients.count)
        for coefficient in coefficients {
            try usage.consumeWork(1)
            values.append(try coefficient.embedded(in: context, maximumDepth: maximumDepth, usage: &usage))
        }
        while let last = values.last {
            if case .zero = try last.sign(maximumDepth: maximumDepth, usage: &usage) { values.removeLast() }
            else { break }
        }
        self.coefficients = values
    }

    /// Receives only owned, same-context buffers whose leading zero trim was verified.
    private init(context: OriginalSingularFieldContext, canonicalCoefficients: [OriginalSingularFieldElement]) {
        self.context = context; self.coefficients = canonicalCoefficients
    }

    package func adding<B: ExactScalarAdmission & ~Copyable>(_ other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
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
    package func negated<B: ExactScalarAdmission & ~Copyable>(maximumDepth: Int, usage: inout B) throws -> Self {
        var values: [OriginalSingularFieldElement] = []
        try RationalAlgebraStorage.retain(coefficients.count, of: OriginalSingularFieldElement.self, usage: &usage)
        values.reserveCapacity(coefficients.count)
        for value in coefficients { values.append(try value.negated(maximumDepth: maximumDepth, usage: &usage)) }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func subtracting<B: ExactScalarAdmission & ~Copyable>(_ other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        try adding(other.negated(maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
    }
    package func multiplied<B: ExactScalarAdmission & ~Copyable>(by other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        try sameContext(other, usage: &usage)
        try usage.checkpoint()
        if isZero || other.isZero { return try Self(context: context, coefficients: [], maximumDepth: maximumDepth, usage: &usage) }
        if degree == 0, try coefficients[0].rationalValue(usage: &usage) == .one {
            _ = try other.coefficients[other.degree].sign(maximumDepth: maximumDepth, usage: &usage)
            return other
        }
        if other.degree == 0, try other.coefficients[0].rationalValue(usage: &usage) == .one {
            _ = try coefficients[degree].sign(maximumDepth: maximumDepth, usage: &usage)
            return self
        }
        let count = try exactScalarCount(coefficients.count, other.degree)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values = Array(repeating: zero, count: count)
        for i in coefficients.indices { for j in other.coefficients.indices {
            try usage.consumeWork(1)
            values[i + j] = try values[i + j].adding(coefficients[i].multiplied(by: other.coefficients[j],
                maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        } }
        return try Self(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    package func differentiated<B: ExactScalarAdmission & ~Copyable>(maximumDepth: Int, usage: inout B) throws -> Self {
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
    package func evaluated<B: ExactScalarAdmission & ~Copyable>(at value: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        var descendant = value.context, target = context
        while true {
            try usage.consumeWork(1)
            if descendant === context { target = value.context; break }
            guard let parent = descendant.parent else { break }
            descendant = parent
        }
        let station = try value.embedded(in: target, maximumDepth: maximumDepth, usage: &usage)
        var result = try OriginalSingularFieldElement.constant(.zero, in: target, maximumDepth: maximumDepth, usage: &usage)
        for coefficient in coefficients.reversed() {
            try usage.consumeWork(1)
            result = try result.multiplied(by: station, maximumDepth: maximumDepth, usage: &usage)
                .adding(coefficient.embedded(in: target, maximumDepth: maximumDepth, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }
    package func divided<B: ExactScalarAdmission & ~Copyable>(by divisor: Self,
        maximumDepth: Int, usage: inout B) throws -> (quotient: Self, remainder: Self) {
        try sameContext(divisor, usage: &usage)
        guard let leading = divisor.coefficients.last else { throw exactScalarBackendFailure("Original tower polynomial divisor is zero.") }
        try usage.checkpoint()
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        let count = degree >= divisor.degree ? try exactScalarCount(degree - divisor.degree, 1) : 0
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var quotient = Array(repeating: zero, count: count)
        try RationalAlgebraStorage.retain(coefficients.count, of: OriginalSingularFieldElement.self, usage: &usage)
        var remainder: [OriginalSingularFieldElement] = []; remainder.reserveCapacity(coefficients.count)
        for coefficient in coefficients { try usage.consumeWork(1); remainder.append(coefficient) }
        while remainder.count > divisor.degree, let value = remainder.last {
            try usage.checkpoint(); try usage.consumeWork(1)
            let oldCount = remainder.count, shift = oldCount - divisor.coefficients.count
            let ratio = try value.divided(by: leading, maximumDepth: maximumDepth, usage: &usage)
            quotient[shift] = ratio
            for index in divisor.coefficients.indices {
                try usage.consumeWork(1)
                let product = try ratio.multiplied(by: divisor.coefficients[index], maximumDepth: maximumDepth, usage: &usage)
                remainder[shift + index] = try remainder[shift + index].subtracting(product,
                    maximumDepth: maximumDepth, usage: &usage)
            }
            while let last = remainder.last {
                if try last.sign(maximumDepth: maximumDepth, usage: &usage) == .zero { remainder.removeLast() }
                else { break }
            }
            guard remainder.count < oldCount else { throw exactScalarBackendFailure("Original tower polynomial division did not lower degree.") }
        }
        while let last = quotient.last {
            if try last.sign(maximumDepth: maximumDepth, usage: &usage) == .zero { quotient.removeLast() }
            else { break }
        }
        return (Self(context: context, canonicalCoefficients: quotient), Self(context: context, canonicalCoefficients: remainder))
    }
    package static func gcd<B: ExactScalarAdmission & ~Copyable>(_ first: Self, _ second: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        var a = first, b = second
        while !b.isZero { let r = try a.divided(by: b, maximumDepth: maximumDepth, usage: &usage).remainder; a = b; b = r }
        return a
    }
    private func coefficient<B: ExactScalarAdmission & ~Copyable>(_ index: Int, maximumDepth: Int,
        usage: inout B) throws -> OriginalSingularFieldElement {
        if index < coefficients.count { return coefficients[index] }
        return try .constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
    }
    private func sameContext<B: ExactScalarAdmission & ~Copyable>(_ other: Self, usage: inout B) throws {
        try usage.consumeWork(1)
        guard context === other.context else { throw exactScalarBackendFailure("Original tower polynomials need the identical immutable field owner.") }
    }
}
