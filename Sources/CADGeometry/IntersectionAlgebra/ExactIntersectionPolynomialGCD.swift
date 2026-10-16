import CADCore

/// Primitive recursive GCD over the original rational multivariate UFD.
package enum ExactIntersectionPolynomialGCD {
    private typealias Polynomial = ExactIntersectionPolynomial
    private enum SpecializedGCD { case unit, factor(Polynomial) }

    package static func gcd<B: ExactScalarAdmission & ~Copyable>(_ first: ExactIntersectionPolynomial,
        _ second: ExactIntersectionPolynomial, usage: inout B) throws -> ExactIntersectionPolynomial {
        try intersectionAlgebraStep(&usage)
        guard first.variableCount == second.variableCount else {
            throw rationalAlgebraFailure("Original polynomial GCD requires one retained ring.")
        }
        if first.isZero { return try second.monic(usage: &usage) }
        if second.isZero { return try first.monic(usage: &usage) }
        if first.isConstant || second.isConstant {
            return try .constant(variableCount: first.variableCount, value: .one, usage: &usage)
        }
        if try first.matches(second, usage: &usage) { return try first.monic(usage: &usage) }
        let firstMask = try coordinateSupport(first, usage: &usage)
        let secondMask = try coordinateSupport(second, usage: &usage)
        if try !firstMask.intersects(secondMask, usage: &usage) {
            return try .constant(variableCount: first.variableCount, value: .one, usage: &usage)
        }
        if let result = try rationalLinearGCD(first, second, mask: firstMask, usage: &usage) { return result }
        if let result = try rationalLinearGCD(second, first, mask: secondMask, usage: &usage) { return result }
        guard let firstAxis = firstMask.last, let secondAxis = secondMask.last else {
            throw rationalAlgebraFailure("Nonconstant GCD lost its original coordinate support.")
        }
        let axis = max(firstAxis, secondAxis)
        guard axis < first.variableCount else {
            throw rationalAlgebraFailure("Nonconstant GCD lost its original main coordinate.")
        }
        if try wholeCoprimeSpecialization(first, second, firstMask: firstMask, secondMask: secondMask, usage: &usage) {
            let unit = try Polynomial.constant(variableCount: first.variableCount, value: .one, usage: &usage)
            try CurrentTaskCancellationChecker().checkCancellation()
            return unit
        }
        let firstContent = try content(first, axis: axis, usage: &usage)
        let secondContent = try content(second, axis: axis, usage: &usage)
        let commonContent = try gcd(firstContent, secondContent, usage: &usage)
        var a = try first.dividedExactly(by: firstContent, usage: &usage).monic(usage: &usage)
        var b = try second.dividedExactly(by: secondContent, usage: &usage).monic(usage: &usage)
        var aDegree = try a.axisCoefficients(at: axis, usage: &usage).count - 1
        var bDegree = try b.axisCoefficients(at: axis, usage: &usage).count - 1
        if aDegree == 0 || bDegree == 0 { return commonContent }
        if let certified = try specializedGCD(a, b, axis: axis,
            singleCoordinate: firstMask.singleAxis == axis && secondMask.singleAxis == axis, usage: &usage) {
            switch certified {
            case .unit: return commonContent
            case .factor(let factor):
                let result = try factor.multiplied(by: commonContent, usage: &usage).monic(usage: &usage)
                try CurrentTaskCancellationChecker().checkCancellation()
                return result
            }
        }
        if aDegree < bDegree { swap(&a, &b); swap(&aDegree, &bDegree) }
        while !b.isZero {
            try intersectionAlgebraStep(&usage)
            if b.isConstant {
                try CurrentTaskCancellationChecker().checkCancellation()
                return commonContent
            }
            let remainder = try pseudoRemainder(a, b, axis: axis, usage: &usage)
            a = b
            if remainder.isZero { b = remainder }
            else {
                b = try remainder.dividedExactly(by: content(remainder, axis: axis, usage: &usage), usage: &usage)
                    .monic(usage: &usage)
            }
        }
        return try a.multiplied(by: commonContent, usage: &usage).monic(usage: &usage)
    }

    package static func squareFree<B: ExactScalarAdmission & ~Copyable>(_ source: ExactIntersectionPolynomial,
        usage: inout B) throws -> ExactIntersectionPolynomial {
        try intersectionAlgebraStep(&usage)
        if source.isZero || source.isConstant { return try source.monic(usage: &usage) }
        let mask = try coordinateSupport(source, usage: &usage)
        var repeated = source
        for axis in 0..<source.variableCount {
            try intersectionAlgebraStep(&usage)
            if try !mask.contains(axis, usage: &usage) { continue }
            repeated = try gcd(repeated, source.differentiated(at: axis, usage: &usage), usage: &usage)
            if repeated.isConstant { break }
        }
        return try source.dividedExactly(by: repeated, usage: &usage).monic(usage: &usage)
    }

    private struct CoordinateSupport {
        let inline: UInt
        let overflow: [Int]
        var last: Int? { overflow.last ?? (inline == 0 ? nil : UInt.bitWidth - inline.leadingZeroBitCount - 1) }
        var singleAxis: Int? {
            if inline == 0 { return overflow.count == 1 ? overflow[0] : nil }
            return overflow.isEmpty && inline.nonzeroBitCount == 1 ? inline.trailingZeroBitCount : nil
        }
        func contains<B: ExactScalarAdmission & ~Copyable>(_ axis: Int, usage: inout B) throws -> Bool {
            if axis < UInt.bitWidth { return inline & (UInt(1) << axis) != 0 }
            var lower = 0, upper = overflow.count
            while lower < upper {
                try intersectionAlgebraStep(&usage)
                let middle = lower + (upper - lower) / 2
                if overflow[middle] < axis { lower = middle + 1 } else { upper = middle }
            }
            return lower < overflow.count && overflow[lower] == axis
        }
        func intersects<B: ExactScalarAdmission & ~Copyable>(_ other: Self, usage: inout B) throws -> Bool {
            if inline & other.inline != 0 { return true }
            var first = 0, second = 0
            while first < overflow.count && second < other.overflow.count {
                try intersectionAlgebraStep(&usage)
                if overflow[first] == other.overflow[second] { return true }
                if overflow[first] < other.overflow[second] { first += 1 } else { second += 1 }
            }
            return false
        }
    }

    private static func coordinateSupport<B: ExactScalarAdmission & ~Copyable>(_ source: Polynomial,
        usage: inout B) throws -> CoordinateSupport {
        let terms = try source.orderedTerms(usage: &usage)
        var inline: UInt = 0, overflow: [Int] = []
        for axis in 0..<source.variableCount {
            for term in terms {
                try intersectionAlgebraStep(&usage)
                if try term.key.exponent(at: axis) == 0 { continue }
                if axis < UInt.bitWidth { inline |= UInt(1) << axis }
                else {
                    try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                    overflow.append(axis)
                }
                break
            }
        }
        return CoordinateSupport(inline: inline, overflow: overflow)
    }

    private static func rationalLinearGCD<B: ExactScalarAdmission & ~Copyable>(_ factor: Polynomial, _ other: Polynomial,
        mask: CoordinateSupport, usage: inout B) throws -> Polynomial? {
        try intersectionAlgebraStep(&usage)
        guard let axis = mask.singleAxis else { return nil }
        let coefficients = try factor.axisCoefficients(at: axis, usage: &usage)
        if coefficients.count != 2 { return nil }
        guard coefficients[0].isConstant, coefficients[1].isConstant,
            let leading = try coefficients[1].leading(usage: &usage)?.coefficient else {
            throw rationalAlgebraFailure("A rational linear support factor lost its exact coefficients.")
        }
        let constant = try coefficients[0].leading(usage: &usage)?.coefficient ?? .zero
        let station = try constant.negated.divided(by: leading, usage: &usage)
        var value = try Polynomial.zero(variableCount: factor.variableCount)
        for coefficient in try other.axisCoefficients(at: axis, usage: &usage).reversed() {
            value = try value.scaled(by: station, usage: &usage).adding(coefficient, usage: &usage)
        }
        if value.isZero { return try factor.monic(usage: &usage) }
        return try .constant(variableCount: factor.variableCount, value: .one, usage: &usage)
    }

    private static func content<B: ExactScalarAdmission & ~Copyable>(_ source: Polynomial, axis: Int,
        usage: inout B) throws -> Polynomial {
        var result = try Polynomial.zero(variableCount: source.variableCount)
        for coefficient in try source.axisCoefficients(at: axis, usage: &usage) where !coefficient.isZero {
            result = try gcd(result, coefficient, usage: &usage)
            if result.isConstant { break }
        }
        return result
    }

    private static func wholeCoprimeSpecialization<B: ExactScalarAdmission & ~Copyable>(_ first: Polynomial, _ second: Polynomial,
        firstMask: CoordinateSupport, secondMask: CoordinateSupport, usage: inout B) throws -> Bool {
        var covered = false
        for axis in 0..<first.variableCount {
            try intersectionAlgebraStep(&usage)
            guard try firstMask.contains(axis, usage: &usage) else { continue }
            guard try secondMask.contains(axis, usage: &usage) else { continue }
            covered = true
            let certificate = try specializedGCD(first, second, axis: axis,
                singleCoordinate: firstMask.singleAxis == axis && secondMask.singleAxis == axis,
                reconstructFactor: false, usage: &usage)
            guard let certificate, case .unit = certificate else { return false }
        }
        return covered
    }

    private static func specializedGCD<B: ExactScalarAdmission & ~Copyable>(_ first: Polynomial, _ second: Polynomial,
        axis: Int, singleCoordinate: Bool, reconstructFactor: Bool = true, usage: inout B) throws -> SpecializedGCD? {
        let a = try first.axisCoefficients(at: axis, usage: &usage)
        let b = try second.axisCoefficients(at: axis, usage: &usage)
        for proposal in 0..<(singleCoordinate ? 2 : 3) {
            try intersectionAlgebraStep(&usage)
            try RationalAlgebraStorage.retain(first.variableCount, of: ExactRationalCoefficient.self, usage: &usage)
            let coordinates: [ExactRationalCoefficient]
            if proposal < 2 {
                coordinates = Array(repeating: proposal == 0 ? .one : .zero, count: first.variableCount)
            } else {
                var distinct: [ExactRationalCoefficient] = []; distinct.reserveCapacity(first.variableCount)
                for coordinate in 0..<first.variableCount {
                    try intersectionAlgebraStep(&usage)
                    distinct.append(try .natural(rationalAlgebraCount(coordinate, 2), usage: &usage))
                }
                coordinates = distinct
            }
            try RationalAlgebraStorage.retain(rationalAlgebraCount(a.count, b.count), of: ExactRationalCoefficient.self, usage: &usage)
            var left: [ExactRationalCoefficient] = [], right: [ExactRationalCoefficient] = []
            left.reserveCapacity(a.count); right.reserveCapacity(b.count)
            for value in a { left.append(try value.evaluated(at: coordinates, usage: &usage)) }
            for value in b { right.append(try value.evaluated(at: coordinates, usage: &usage)) }
            guard let aLead = left.last, let bLead = right.last, !aLead.isZero, !bLead.isZero else { continue }
            guard let probe = try ExactIntersectionModularCoprimality.prepare(left, right, usage: &usage) else { continue }
            if probe.degree == 0 { return .unit }
            if singleCoordinate && reconstructFactor {
                var bound: UInt64 = 1
                while bound <= (ExactIntersectionModularCoprimality.prime - 1) / 2 / bound {
                    try intersectionAlgebraStep(&usage)
                    if let receipt = try ExactIntersectionModularCoprimality.factorReceipt(probe,
                        first: left, second: right, denominatorBound: bound, usage: &usage) {
                        let factor = try polynomial(receipt.coefficients, axis: axis,
                            variableCount: first.variableCount, usage: &usage)
                        let firstQuotient = try polynomial(receipt.firstQuotient, axis: axis,
                            variableCount: first.variableCount, usage: &usage)
                        let secondQuotient = try polynomial(receipt.secondQuotient, axis: axis,
                            variableCount: second.variableCount, usage: &usage)
                        guard receipt.coefficients.count - 1 == probe.degree,
                              try factor.multiplied(by: firstQuotient, usage: &usage).matches(first, usage: &usage),
                              try factor.multiplied(by: secondQuotient, usage: &usage).matches(second, usage: &usage) else {
                            throw rationalAlgebraFailure("A modular factor receipt lost its original exact reconstruction.")
                        }
                        try CurrentTaskCancellationChecker().checkCancellation()
                        return .factor(factor)
                    }
                    bound *= 2
                }
            }
        }
        return nil
    }

    private static func polynomial<B: ExactScalarAdmission & ~Copyable>(_ coefficients: [ExactRationalCoefficient],
        axis: Int, variableCount: Int, usage: inout B) throws -> Polynomial {
        var result = try Polynomial.zero(variableCount: variableCount)
        for (exponent, coefficient) in coefficients.enumerated() {
            try intersectionAlgebraStep(&usage)
            if coefficient.isZero { continue }
            let term = try Polynomial.monomial(variableCount: variableCount,
                power: .coordinate(at: axis, exponent: exponent, variableCount: variableCount, usage: &usage),
                coefficient: coefficient, usage: &usage)
            result = try result.adding(term, usage: &usage)
        }
        return result
    }

    private static func pseudoRemainder<B: ExactScalarAdmission & ~Copyable>(_ source: Polynomial, _ divisor: Polynomial,
        axis: Int, usage: inout B) throws -> Polynomial {
        let coefficients = try divisor.axisCoefficients(at: axis, usage: &usage)
        guard let lead = coefficients.last else { throw rationalAlgebraFailure("Original pseudo-division has a zero divisor.") }
        let divisorDegree = coefficients.count - 1
        var remainder = source
        while !remainder.isZero {
            try intersectionAlgebraStep(&usage)
            let values = try remainder.axisCoefficients(at: axis, usage: &usage)
            let degree = values.count - 1
            if degree < divisorDegree { break }
            guard let numeratorLead = values.last else { throw rationalAlgebraFailure("Original pseudo-division lost its leading coefficient.") }
            let shift = degree - divisorDegree
            let factor = try Polynomial.monomial(variableCount: source.variableCount,
                power: Polynomial.Power.coordinate(at: axis, exponent: shift,
                    variableCount: source.variableCount, usage: &usage),
                coefficient: .one, usage: &usage)
            remainder = try remainder.multiplied(by: lead, usage: &usage)
                .subtracting(divisor.multiplied(by: numeratorLead, usage: &usage).multiplied(by: factor, usage: &usage), usage: &usage)
            guard try remainder.isZero || (remainder.axisCoefficients(at: axis, usage: &usage).count - 1) < degree else {
                throw rationalAlgebraFailure("Original pseudo-remainder failed strict main-degree descent.")
            }
        }
        return remainder
    }
}
