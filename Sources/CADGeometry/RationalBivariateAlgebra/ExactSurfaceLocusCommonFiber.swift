/// Generic original common fibers on exact source loci, with every exceptional coefficient retained.
package struct ExactSurfaceLocusCommonFiber: Sendable {
    package struct Component: Sendable {
        package let originalLocus: ExactBivariatePolynomial
        package let horizontal: ExactSurfaceCoefficientPolynomial
        package let vertical: ExactSurfaceCoefficientPolynomial
        package let common: ExactSurfaceCoefficientPolynomial
        package let exceptionalCoefficients: [ExactBivariatePolynomial]
        package var hasWholeParameterFiber: Bool { common.isZero }
    }
    package let components: [Component]

    package init<B: ExactScalarAdmission & ~Copyable>(locus: ExactBivariatePolynomial,
        horizontal: ExactSurfaceCoefficientPolynomial, vertical: ExactSurfaceCoefficientPolynomial,
        usage: inout B) throws {
        guard !locus.isZero, locus.uDegree > 0 || locus.vDegree > 0 else {
            throw rationalAlgebraFailure("Original quotient fibers require a nonconstant original locus.")
        }
        let authority = try OriginalRationalZeroSetAuthority(original: locus, usage: &usage)
        var pending: [ExactBivariatePolynomial] = []
        try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
        pending.append(authority.squareFree)
        var result: [Component] = []
        while let factor = pending.popLast() {
            try usage.consumeWork(1)
            let content = try ExactBivariateGCD().content(factor, usage: &usage)
            if content.uDegree > 0, factor.vDegree > 0 {
                let remaining = try factor.dividedExactly(by: content, usage: &usage)
                try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
                pending.append(content); pending.append(remaining); continue
            }
            let exchanged = factor.vDegree <= 0
            let selected = try exchanged ? factor.exchangedAxes(usage: &usage) : factor
            let first = try exchanged ? Self.exchanged(horizontal, usage: &usage) : horizontal
            let second = try exchanged ? Self.exchanged(vertical, usage: &usage) : vertical
            do {
                var exceptional: [ExactBivariatePolynomial] = []
                var a = try Self.residues(first, modulo: selected, exceptional: &exceptional, usage: &usage)
                var b = try Self.residues(second, modulo: selected, exceptional: &exceptional, usage: &usage)
                if a.count < b.count { swap(&a, &b) }
                while !b.isEmpty {
                    let next = try Self.remainder(a, by: b, modulo: selected,
                        exceptional: &exceptional, usage: &usage)
                    a = b; b = next
                }
                let common = try Self.cleared(a, usage: &usage)
                if let leading = common.coefficients.last,
                    leading.uDegree > 0 || leading.vDegree > 0 {
                    try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
                    exceptional.append(leading)
                }
                let output = try exchanged ? Self.exchanged(common, usage: &usage) : common
                var nativeExceptional: [ExactBivariatePolynomial] = []
                try RationalAlgebraStorage.retain(exceptional.count, of: ExactBivariatePolynomial.self, usage: &usage)
                nativeExceptional.reserveCapacity(exceptional.count)
                for coefficient in exceptional {
                    nativeExceptional.append(try exchanged ? coefficient.exchangedAxes(usage: &usage) : coefficient)
                }
                try RationalAlgebraStorage.retain(1, of: Component.self, usage: &usage)
                result.append(.init(originalLocus: factor, horizontal: horizontal, vertical: vertical,
                    common: output, exceptionalCoefficients: nativeExceptional))
            } catch let split as Split {
                let shared = try exchanged ? split.factor.exchangedAxes(usage: &usage) : split.factor
                let remaining = try factor.dividedExactly(by: shared, usage: &usage)
                guard !remaining.isZero, remaining.uDegree > 0 || remaining.vDegree > 0,
                    shared.uDegree > 0 || shared.vDegree > 0 else {
                    throw rationalAlgebraFailure("Original quotient zero-divisor split did not produce proper factors.")
                }
                try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
                pending.append(shared); pending.append(remaining)
            }
        }
        components = result
    }

    /// Splits original zero divisors before issuing square-free generic parameter fibers.
    package static func squareFreeParameters<B: ExactScalarAdmission & ~Copyable>(component: Component,
        usage: inout B) throws -> [Component] {
        try RationalAlgebraStorage.retain(1, of: Component.self, usage: &usage)
        var pending = [component], output: [Component] = []
        while let current = pending.popLast() {
            try usage.consumeWork(1)
            do {
                let value = try squareFreeParameter(component: current, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Component.self, usage: &usage)
                output.append(value)
            } catch let split as Split {
                let factor = try current.originalLocus.vDegree <= 0 ? split.factor.exchangedAxes(usage: &usage) : split.factor
                let remaining = try current.originalLocus.dividedExactly(by: factor, usage: &usage)
                guard factor.uDegree > 0 || factor.vDegree > 0,
                    remaining.uDegree > 0 || remaining.vDegree > 0 else {
                    throw rationalAlgebraFailure("Original square-free zero divisor split is not proper.")
                }
                for index in 0..<2 {
                    let locus = index == 0 ? factor : remaining
                    let children = try Self(locus: locus, horizontal: current.horizontal,
                        vertical: current.vertical, usage: &usage)
                    try RationalAlgebraStorage.retain(children.components.count, of: Component.self, usage: &usage)
                    pending.append(contentsOf: children.components)
                }
            }
        }
        return output
    }

    /// Removes repeated edge-parameter factors in the ORIGINAL locus quotient.
    private static func squareFreeParameter<B: ExactScalarAdmission & ~Copyable>(component: Component,
        usage: inout B) throws -> Component {
        if component.common.degree <= 0 { return component }
        let exchanged = component.originalLocus.vDegree <= 0
        let locus = try exchanged ? component.originalLocus.exchangedAxes(usage: &usage) : component.originalLocus
        let source = try exchanged ? Self.exchanged(component.common, usage: &usage) : component.common
        var exceptional = component.exceptionalCoefficients
        if exchanged {
            try RationalAlgebraStorage.retain(exceptional.count, of: ExactBivariatePolynomial.self, usage: &usage)
            var transformed: [ExactBivariatePolynomial] = []; transformed.reserveCapacity(exceptional.count)
            for value in exceptional { transformed.append(try value.exchangedAxes(usage: &usage)) }
            exceptional = transformed
        }
        let values = try residues(source, modulo: locus, exceptional: &exceptional, usage: &usage)
        try RationalAlgebraStorage.retain(max(0, source.degree), of: ExactBivariatePolynomial.self, usage: &usage)
        var derivative: [ExactBivariatePolynomial] = []; derivative.reserveCapacity(max(0, source.degree))
        if source.degree > 0 { for index in 1...source.degree {
            derivative.append(try source.coefficients[index].scaled(by: .natural(index, usage: &usage), usage: &usage))
        } }
        var a = values
        var b = try residues(.init(coefficients: derivative, usage: &usage), modulo: locus,
            exceptional: &exceptional, usage: &usage)
        while !b.isEmpty {
            let next = try remainder(a, by: b, modulo: locus, exceptional: &exceptional, usage: &usage)
            a = b; b = next
        }
        var quotient = values
        if a.count > 1 {
            quotient = try divided(values, by: a, modulo: locus, exceptional: &exceptional, usage: &usage)
        }
        let common = try cleared(quotient, usage: &usage)
        let output = try exchanged ? Self.exchanged(common, usage: &usage) : common
        if exchanged {
            try RationalAlgebraStorage.retain(exceptional.count, of: ExactBivariatePolynomial.self, usage: &usage)
            var restored: [ExactBivariatePolynomial] = []; restored.reserveCapacity(exceptional.count)
            for value in exceptional { restored.append(try value.exchangedAxes(usage: &usage)) }
            exceptional = restored
        }
        try RationalAlgebraStorage.retain(1, of: Component.self, usage: &usage)
        return .init(originalLocus: component.originalLocus, horizontal: component.horizontal,
            vertical: component.vertical, common: output, exceptionalCoefficients: exceptional)
    }

    private static func divided<B: ExactScalarAdmission & ~Copyable>(_ original: [Residue], by divisor: [Residue],
        modulo locus: ExactBivariatePolynomial, exceptional: inout [ExactBivariatePolynomial],
        usage: inout B) throws -> [Residue] {
        guard let lead = divisor.last, !lead.isZero, original.count >= divisor.count else {
            throw rationalAlgebraFailure("Original quotient square-free divisor has no lawful leading coefficient.")
        }
        let count = try rationalAlgebraCount(original.count - divisor.count, 1)
        try RationalAlgebraStorage.retain(count, of: Residue.self, usage: &usage)
        let zero = Residue(numerator: .zero, denominator: try .constant(.one, usage: &usage))
        var quotient = [Residue](repeating: zero, count: count)
        var remainder = original
        try RationalAlgebraStorage.retain(original.count, of: Residue.self, usage: &usage)
        if lead.numerator.uDegree > 0 || lead.numerator.vDegree > 0 {
            try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
            exceptional.append(lead.numerator)
        }
        while remainder.count >= divisor.count, let top = remainder.last {
            let previousCount = remainder.count, shift = previousCount - divisor.count
            for index in quotient.indices {
                quotient[index] = try multiplied(quotient[index], lead, modulo: locus,
                    exceptional: &exceptional, usage: &usage)
            }
            quotient[shift] = try subtracted(quotient[shift],
                Residue(numerator: top.numerator.scaled(by: .one.negated, usage: &usage), denominator: top.denominator),
                modulo: locus, exceptional: &exceptional, usage: &usage)
            for index in remainder.indices {
                remainder[index] = try multiplied(remainder[index], lead, modulo: locus,
                    exceptional: &exceptional, usage: &usage)
            }
            for index in divisor.indices {
                remainder[index + shift] = try subtracted(remainder[index + shift],
                    multiplied(top, divisor[index], modulo: locus, exceptional: &exceptional, usage: &usage),
                    modulo: locus, exceptional: &exceptional, usage: &usage)
            }
            try trim(&remainder, usage: &usage)
            guard remainder.count < previousCount else {
                throw rationalAlgebraFailure("Original quotient division did not reduce separate-parameter degree.")
            }
        }
        guard remainder.isEmpty else { throw rationalAlgebraFailure("Original quotient repeated factor does not divide its original source.") }
        try trim(&quotient, usage: &usage)
        return quotient
    }

    private struct Split: Error, Sendable { let factor: ExactBivariatePolynomial }
    private struct Residue: Sendable {
        let numerator: ExactBivariatePolynomial
        let denominator: ExactBivariatePolynomial
        var isZero: Bool { numerator.isZero }
    }
    private static func exchanged<B: ExactScalarAdmission & ~Copyable>(_ source: ExactSurfaceCoefficientPolynomial,
        usage: inout B) throws -> ExactSurfaceCoefficientPolynomial {
        try RationalAlgebraStorage.retain(source.coefficients.count, of: ExactBivariatePolynomial.self, usage: &usage)
        var values: [ExactBivariatePolynomial] = []; values.reserveCapacity(source.coefficients.count)
        for value in source.coefficients { values.append(try value.exchangedAxes(usage: &usage)) }
        return try .init(coefficients: values, usage: &usage)
    }

    private static func reduced<B: ExactScalarAdmission & ~Copyable>(_ numerator: ExactBivariatePolynomial,
        denominator: ExactBivariatePolynomial, modulo locus: ExactBivariatePolynomial,
        exceptional: inout [ExactBivariatePolynomial], usage: inout B) throws -> Residue {
        var n = numerator, d = denominator
        guard !d.isZero, locus.vDegree > 0 else {
            throw rationalAlgebraFailure("Original quotient residue has a zero denominator or invalid selected axis.")
        }
        let lead = try locus.coefficient(ofV: locus.vDegree, usage: &usage)
        while !n.isZero, n.vDegree >= locus.vDegree {
            let degree = n.vDegree
            let coefficient = try n.coefficient(ofV: degree, usage: &usage)
            n = try n.multiplied(by: lead, usage: &usage)
                .subtracting(locus.multiplied(by: coefficient, usage: &usage)
                    .shiftedV(degree - locus.vDegree, usage: &usage), usage: &usage)
            d = try d.multiplied(by: lead, usage: &usage)
            guard n.isZero || n.vDegree < degree else {
                throw rationalAlgebraFailure("Original quotient pseudo-reduction did not lower its source degree.")
            }
        }
        if !n.isZero {
            let shared = try ExactBivariateGCD().greatestCommonDivisor(locus, n, usage: &usage)
            if shared.uDegree > 0 || shared.vDegree > 0 { throw Split(factor: shared) }
        }
        if !d.isZero, d.uDegree > 0 || d.vDegree > 0 {
            try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
            exceptional.append(d)
        }
        return .init(numerator: n, denominator: d)
    }
    private static func residues<B: ExactScalarAdmission & ~Copyable>(_ source: ExactSurfaceCoefficientPolynomial,
        modulo locus: ExactBivariatePolynomial, exceptional: inout [ExactBivariatePolynomial],
        usage: inout B) throws -> [Residue] {
        let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        var values: [Residue] = []
        try RationalAlgebraStorage.retain(source.coefficients.count, of: Residue.self, usage: &usage)
        values.reserveCapacity(source.coefficients.count)
        for value in source.coefficients {
            values.append(try reduced(value, denominator: one, modulo: locus,
                exceptional: &exceptional, usage: &usage))
        }
        try trim(&values, usage: &usage)
        return values
    }
    private static func multiplied<B: ExactScalarAdmission & ~Copyable>(_ a: Residue, _ b: Residue,
        modulo locus: ExactBivariatePolynomial, exceptional: inout [ExactBivariatePolynomial],
        usage: inout B) throws -> Residue {
        try reduced(a.numerator.multiplied(by: b.numerator, usage: &usage),
            denominator: a.denominator.multiplied(by: b.denominator, usage: &usage),
            modulo: locus, exceptional: &exceptional, usage: &usage)
    }
    private static func subtracted<B: ExactScalarAdmission & ~Copyable>(_ a: Residue, _ b: Residue,
        modulo locus: ExactBivariatePolynomial, exceptional: inout [ExactBivariatePolynomial],
        usage: inout B) throws -> Residue {
        try reduced(a.numerator.multiplied(by: b.denominator, usage: &usage)
            .subtracting(b.numerator.multiplied(by: a.denominator, usage: &usage), usage: &usage),
            denominator: a.denominator.multiplied(by: b.denominator, usage: &usage),
            modulo: locus, exceptional: &exceptional, usage: &usage)
    }
    private static func trim<B: ExactScalarAdmission & ~Copyable>(_ values: inout [Residue], usage: inout B) throws {
        while let value = values.last { try usage.consumeWork(1); if value.isZero { values.removeLast() } else { break } }
    }
    private static func remainder<B: ExactScalarAdmission & ~Copyable>(_ numerator: [Residue], by divisor: [Residue],
        modulo locus: ExactBivariatePolynomial, exceptional: inout [ExactBivariatePolynomial],
        usage: inout B) throws -> [Residue] {
        guard let lead = divisor.last, !lead.isZero else { throw rationalAlgebraFailure("Original quotient parameter divisor is zero.") }
        // Outside this exact coefficient's zero set, pseudo-division preserves all common roots.
        if lead.numerator.uDegree > 0 || lead.numerator.vDegree > 0 {
            try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
            exceptional.append(lead.numerator)
        }
        try RationalAlgebraStorage.retain(numerator.count, of: Residue.self, usage: &usage)
        var values = numerator
        while values.count >= divisor.count, let top = values.last {
            let count = values.count, shift = count - divisor.count
            for index in values.indices {
                values[index] = try multiplied(values[index], lead, modulo: locus,
                    exceptional: &exceptional, usage: &usage)
            }
            for index in divisor.indices {
                let term = try multiplied(top, divisor[index], modulo: locus,
                    exceptional: &exceptional, usage: &usage)
                values[shift + index] = try subtracted(values[shift + index], term, modulo: locus,
                    exceptional: &exceptional, usage: &usage)
            }
            try trim(&values, usage: &usage)
            guard values.count < count else { throw rationalAlgebraFailure("Original quotient parameter PRS did not reduce degree.") }
        }
        return values
    }
    private static func cleared<B: ExactScalarAdmission & ~Copyable>(_ source: [Residue],
        usage: inout B) throws -> ExactSurfaceCoefficientPolynomial {
        var values: [ExactBivariatePolynomial] = []
        try RationalAlgebraStorage.retain(source.count, of: ExactBivariatePolynomial.self, usage: &usage)
        values.reserveCapacity(source.count)
        for index in source.indices {
            var numerator = source[index].numerator
            for other in source.indices where other != index {
                try usage.consumeWork(1)
                numerator = try numerator.multiplied(by: source[other].denominator, usage: &usage)
            }
            values.append(numerator)
        }
        return try .init(coefficients: values, usage: &usage)
    }
}
