import CADCore

/// Affine scalar chart arithmetic shared by persistent original image laws.
enum OriginalParameterImageMap {
    static func validate(gain: OriginalParameterGain, offset: Double) throws {
        try gain.validate()
        guard offset.isFinite else {
            throw GeometryConversionError.invalidInput("An original parameter image requires a finite nonzero signed gain and finite offset.")
        }
    }

    private struct BorrowedWork: RationalAlgebraAdmitting {
        let consume: () throws -> Void
        mutating func visitExactCell(depth: Int) throws { try consume() }
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original chart work count is negative.") }
            for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try consume() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            // Original word allocation is admitted before allocation by the same
            // caller operation; no separate work or storage allowance is created.
            try consumeExactWork(count)
        }
    }

    private static func mappedComparison(_ foreign: Double, native: Double,
        gain: OriginalParameterGain, offset: Double, consumeWork: () throws -> Void) throws -> RobustSign {
        switch gain {
        case .product, .difference:
            return try withoutActuallyEscaping(consumeWork) { work in
                var usage = BorrowedWork(consume: work)
                let mapped = try gain.exactCoefficient(usage: &usage)
                    .multiplied(by: .originalDouble(foreign, usage: &usage), usage: &usage)
                    .adding(.originalDouble(offset, usage: &usage), usage: &usage)
                let difference = try mapped.subtracting(.originalDouble(native, usage: &usage), usage: &usage)
                return difference.isZero ? .zero : difference.isPositive ? .positive : .negative
            }
        case .binary, .ratio: break
        }
        let pair = gain.coefficients
        let original = FloatingPointExpansion.sum(
            FloatingPointExpansion.product([offset], [pair.denominator]),
            FloatingPointExpansion.product([pair.numerator], [foreign]))
        return FloatingPointExpansion.sign(FloatingPointExpansion.subtract(original,
            FloatingPointExpansion.product([native], [pair.denominator])))
    }

    static func originalSpanFitsPeriod(_ interval: ScalarInterval,
        gain: OriginalParameterGain, originalSourcePeriod: Double,
        consumeWork: () throws -> Void) throws -> Bool {
        try gain.validate()
        guard interval.lower.isFinite, interval.upper.isFinite,
              interval.lower <= interval.upper, originalSourcePeriod.isFinite,
              originalSourcePeriod > 0 else {
            throw GeometryConversionError.invalidInput("Original periodic span requires finite ordered endpoints and a positive native period.")
        }
        return try withoutActuallyEscaping(consumeWork) { work in
            var usage = BorrowedWork(consume: work)
            let difference = try ExactRationalCoefficient.originalDouble(interval.upper, usage: &usage)
                .subtracting(.originalDouble(interval.lower, usage: &usage), usage: &usage)
            let directedSpan = try gain.exactCoefficient(usage: &usage)
                .multiplied(by: difference, usage: &usage)
            let span = directedSpan.isNegative ? directedSpan.negated : directedSpan
            let excess = try span.subtracting(.originalDouble(originalSourcePeriod, usage: &usage),
                usage: &usage)
            return !excess.isPositive
        }
    }

    static func domain(_ source: ParameterDomain, gain: OriginalParameterGain, offset: Double) -> ParameterDomain {
        let pair = gain.coefficients
        switch source {
        case .unbounded: return .unbounded
        case .periodic(let period): return .periodic(period: (period / abs(pair.numerator)) * pair.denominator)
        case .closed(let lower, let upper):
            let a = ((lower - offset) / pair.numerator) * pair.denominator
            let b = ((upper - offset) / pair.numerator) * pair.denominator
            return .closed(min(a, b), max(a, b))
        }
    }

    static func parameter(_ value: Double, gain: OriginalParameterGain, offset: Double) throws -> Double {
        let pair = gain.coefficients
        let result = offset + (value / pair.denominator) * pair.numerator
        guard value.isFinite, result.isFinite else {
            throw GeometryConversionError.invalidInput("Original parameter image arithmetic is nonfinite.")
        }
        return result
    }

    static func interval<B: RationalAlgebraAdmitting>(_ value: ScalarInterval,
        gain: OriginalParameterGain, offset: Double, sourceDomain: ParameterDomain,
        usage: inout B) throws -> ScalarInterval {
        try usage.visitExactCell(depth: 0)
        let coefficient = try gain.exactCoefficient(usage: &usage)
        guard !coefficient.isZero, offset.isFinite,
            value.lower.isFinite, value.upper.isFinite, value.lower <= value.upper else {
            throw GeometryConversionError.invalidInput("Original affine interval requires finite ordered source and nonzero gain.")
        }
        let origin = try ExactRationalCoefficient.originalDouble(offset, usage: &usage)
        let first = try coefficient.multiplied(by: .originalDouble(value.lower, usage: &usage), usage: &usage)
            .adding(origin, usage: &usage)
        let last = try coefficient.multiplied(by: .originalDouble(value.upper, usage: &usage), usage: &usage)
            .adding(origin, usage: &usage)
        let lower = coefficient.isNegative ? last : first
        let upper = coefficient.isNegative ? first : last
        var lowerBound = try lower.outwardInterval(usage: &usage).lower
        var upperBound = try upper.outwardInterval(usage: &usage).upper
        if case .closed(let sourceLower, let sourceUpper) = sourceDomain {
            guard sourceLower.isFinite, sourceUpper.isFinite, sourceLower <= sourceUpper else {
                throw GeometryConversionError.invalidInput("Original affine image has an invalid closed source domain.")
            }
            let low = try lower.subtracting(.originalDouble(sourceLower, usage: &usage), usage: &usage)
            let high = try upper.subtracting(.originalDouble(sourceUpper, usage: &usage), usage: &usage)
            guard !low.isNegative, !high.isPositive else {
                throw GeometryConversionError.invalidInput("Original parameter image exceeds its exact native source domain.")
            }
            lowerBound = max(sourceLower, lowerBound)
            upperBound = min(sourceUpper, upperBound)
        }
        if value.lower == value.upper {
            if try lower.subtracting(.originalDouble(lowerBound, usage: &usage), usage: &usage).isZero {
                return try ScalarInterval(lower: lowerBound, upper: lowerBound)
            }
            if try lower.subtracting(.originalDouble(upperBound, usage: &usage), usage: &usage).isZero {
                return try ScalarInterval(lower: upperBound, upper: upperBound)
            }
        }
        return try ScalarInterval(lower: lowerBound, upper: upperBound)
    }

    static func inverseInterval<B: RationalAlgebraAdmitting>(_ native: ScalarInterval,
        gain: OriginalParameterGain, offset: Double, usage: inout B) throws -> ScalarInterval {
        try usage.visitExactCell(depth: 0)
        let coefficient = try gain.exactCoefficient(usage: &usage)
        guard !coefficient.isZero, offset.isFinite,
            native.lower.isFinite, native.upper.isFinite, native.lower <= native.upper else {
            throw GeometryConversionError.invalidInput("Original inverse affine interval requires finite ordered source and nonzero gain.")
        }
        let origin = try ExactRationalCoefficient.originalDouble(offset, usage: &usage)
        let first = try ExactRationalCoefficient.originalDouble(native.lower, usage: &usage)
            .subtracting(origin, usage: &usage).divided(by: coefficient, usage: &usage)
        let last = try ExactRationalCoefficient.originalDouble(native.upper, usage: &usage)
            .subtracting(origin, usage: &usage).divided(by: coefficient, usage: &usage)
        let lower = coefficient.isNegative ? last : first
        let upper = coefficient.isNegative ? first : last
        let lowerBound = try lower.outwardInterval(usage: &usage).lower
        let upperBound = try upper.outwardInterval(usage: &usage).upper
        if native.lower == native.upper {
            if try lower.subtracting(.originalDouble(lowerBound, usage: &usage), usage: &usage).isZero {
                return try ScalarInterval(lower: lowerBound, upper: lowerBound)
            }
            if try lower.subtracting(.originalDouble(upperBound, usage: &usage), usage: &usage).isZero {
                return try ScalarInterval(lower: upperBound, upper: upperBound)
            }
        }
        return try ScalarInterval(lower: lowerBound, upper: upperBound)
    }

    static func inverseInterval(_ native: ScalarInterval, gain: OriginalParameterGain,
        offset: Double, consumeWork: () throws -> Void = {}) throws -> ScalarInterval {
        try validate(gain: gain, offset: offset)
        let pair = gain.coefficients
        let difference = OutwardScalarInterval(lower: native.lower, upper: native.upper) - .exact(offset)
        let bounds: OutwardScalarInterval?
        switch gain {
        case .product, .difference: bounds = difference.divided(by: try gain.interval())
        case .binary, .ratio: bounds = (difference * .exact(pair.denominator)).divided(by: .exact(pair.numerator))
        }
        guard let bounds, bounds.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original inverse parameter bounds are nonfinite.")
        }
        if native.lower == native.upper {
            let candidate = ((native.lower - offset) / pair.numerator) * pair.denominator
            if candidate.isFinite {
                if try mappedComparison(candidate, native: native.lower, gain: gain,
                    offset: offset, consumeWork: consumeWork) == .zero {
                    return try ScalarInterval(lower: candidate, upper: candidate)
                }
            }
        }
        return try ScalarInterval(lower: bounds.lower, upper: bounds.upper)
    }

    static func interval(_ value: ScalarInterval, gain: OriginalParameterGain, offset: Double,
        sourceDomain: ParameterDomain, consumeWork: () throws -> Void = {}) throws -> ScalarInterval {
        let mapped = OutwardScalarInterval.exact(offset)
            + (try gain.interval()) * OutwardScalarInterval(lower: value.lower, upper: value.upper)
        guard mapped.isFinite else {
            throw GeometryConversionError.invalidInput("Original parameter image interval arithmetic is nonfinite.")
        }
        if value.lower == value.upper {
            let candidate = try parameter(value.lower, gain: gain, offset: offset)
            if try mappedComparison(value.lower, native: candidate, gain: gain, offset: offset,
                consumeWork: consumeWork) == .zero {
                if case .closed(let lower, let upper) = sourceDomain,
                    candidate < lower || candidate > upper {
                    throw GeometryConversionError.invalidInput("Original singleton image exceeds its native source domain.")
                }
                return try ScalarInterval(lower: candidate, upper: candidate)
            }
        }
        if case .closed(let lower, let upper) = sourceDomain {
            for endpoint in [value.lower, value.upper] {
                try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
                let low = try mappedComparison(endpoint, native: lower, gain: gain,
                    offset: offset, consumeWork: consumeWork)
                let high = try mappedComparison(endpoint, native: upper, gain: gain,
                    offset: offset, consumeWork: consumeWork)
                if value.lower == value.upper {
                    if low == .zero { return try ScalarInterval(lower: lower, upper: lower) }
                    if high == .zero { return try ScalarInterval(lower: upper, upper: upper) }
                }
                guard low == .positive || low == .zero,
                      high == .negative || high == .zero else {
                    throw GeometryConversionError.invalidInput("Original parameter image exceeds its exact native source domain.")
                }
            }
            return try ScalarInterval(lower: max(lower, mapped.lower), upper: min(upper, mapped.upper))
        }
        return try ScalarInterval(lower: mapped.lower, upper: mapped.upper)
    }
}
