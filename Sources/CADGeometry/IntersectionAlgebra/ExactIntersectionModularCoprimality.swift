import CADCore

/// Sufficient rational GCD certificates from degree-preserving modular probes.
package enum ExactIntersectionModularCoprimality {
    // Exact trial division by every integer 2...256 proves this fixed prime.
    // Residue products are <= 2^32; base-2^32 word reduction stays below 2^49.
    package static let prime: UInt64 = 65_537

    package struct Probe: Sendable {
        let coefficients: [UInt64]
        var degree: Int { coefficients.count - 1 }
    }

    package struct FactorReceipt: Sendable {
        let coefficients: [ExactRationalCoefficient]
        let firstQuotient: [ExactRationalCoefficient]
        let secondQuotient: [ExactRationalCoefficient]
    }

    package static func certifies<B: ExactScalarAdmission & ~Copyable>(
        _ first: [ExactRationalCoefficient], _ second: [ExactRationalCoefficient],
        usage: inout B) throws -> Bool {
        try prepare(first, second, usage: &usage)?.degree == 0
    }

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(
        _ first: [ExactRationalCoefficient], _ second: [ExactRationalCoefficient],
        usage: inout B) throws -> Probe? {
        try intersectionAlgebraStep(&usage)
        let result = try probe(first, second, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    private static func probe<B: ExactScalarAdmission & ~Copyable>(
        _ first: [ExactRationalCoefficient], _ second: [ExactRationalCoefficient],
        usage: inout B) throws -> Probe? {
        guard !first.isEmpty, !second.isEmpty else { return nil }
        guard var left = try residues(first, usage: &usage),
            var right = try residues(second, usage: &usage),
            left.last != 0, right.last != 0 else { return nil }
        while !right.isEmpty {
            try intersectionAlgebraStep(&usage)
            // Mutation detaches the complete borrowed buffer, not one slot.
            try RationalAlgebraStorage.retain(left.count, of: UInt64.self, usage: &usage)
            var remainder = left
            guard let leading = right.last, leading != 0 else {
                throw rationalAlgebraFailure("A modular GCD lost its nonzero leading coefficient.")
            }
            let inverse = try power(leading, exponent: prime - 2, usage: &usage)
            while remainder.count >= right.count, let top = remainder.last {
                try intersectionAlgebraStep(&usage)
                let previousCount = remainder.count
                let shift = previousCount - right.count
                let ratio = try multiplied(top, inverse, usage: &usage)
                for index in right.indices {
                    let term = try multiplied(ratio, right[index], usage: &usage)
                    try intersectionAlgebraStep(&usage)
                    let value = remainder[index + shift]
                    remainder[index + shift] = value >= term ? value - term : prime - (term - value)
                }
                while let last = remainder.last, last == 0 {
                    try intersectionAlgebraStep(&usage)
                    remainder.removeLast()
                }
                guard remainder.count < previousCount else {
                    throw rationalAlgebraFailure("A modular remainder lost strict degree descent.")
                }
            }
            left = right; right = remainder
        }
        // Invertible denominators and retained degrees commute with the
        // Sylvester resultant. A nonzero finite-field resultant implies the
        // original rational resultant is nonzero, hence its GCD is a unit.
        if left.count > 1, let leading = left.last, leading != 1 {
            try RationalAlgebraStorage.retain(left.count, of: UInt64.self, usage: &usage)
            let inverse = try power(leading, exponent: prime - 2, usage: &usage)
            for index in left.indices { left[index] = try multiplied(left[index], inverse, usage: &usage) }
        }
        try RationalAlgebraStorage.retain(1, of: Probe.self, usage: &usage)
        return Probe(coefficients: left)
    }

    /// A candidate is sufficient only with both exact quotient receipts.
    package static func factorReceipt<B: ExactScalarAdmission & ~Copyable>(_ probe: Probe,
        first: [ExactRationalCoefficient], second: [ExactRationalCoefficient],
        denominatorBound: UInt64, usage: inout B) throws -> FactorReceipt? {
        try intersectionAlgebraStep(&usage)
        let result = try reconstructedFactor(probe, first: first, second: second,
            denominatorBound: denominatorBound, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    private static func reconstructedFactor<B: ExactScalarAdmission & ~Copyable>(_ probe: Probe,
        first: [ExactRationalCoefficient], second: [ExactRationalCoefficient],
        denominatorBound: UInt64, usage: inout B) throws -> FactorReceipt? {
        guard probe.degree > 0, first.last == .one, second.last == .one,
              denominatorBound > 0, denominatorBound <= (prime - 1) / 2 / denominatorBound else { return nil }
        let numeratorBound = (prime - 1) / (2 * denominatorBound)
        try RationalAlgebraStorage.retain(probe.coefficients.count, of: ExactRationalCoefficient.self, usage: &usage)
        var candidate: [ExactRationalCoefficient] = []; candidate.reserveCapacity(probe.coefficients.count)
        for residue in probe.coefficients {
            guard let coefficient = try reconstructed(residue, numeratorBound: numeratorBound,
                denominatorBound: denominatorBound, usage: &usage) else { return nil }
            candidate.append(coefficient)
        }
        guard candidate.last == .one,
              let firstQuotient = try quotient(first, by: candidate, usage: &usage),
              let secondQuotient = try quotient(second, by: candidate, usage: &usage) else { return nil }
        try RationalAlgebraStorage.retain(1, of: FactorReceipt.self, usage: &usage)
        return FactorReceipt(coefficients: candidate, firstQuotient: firstQuotient, secondQuotient: secondQuotient)
    }

    private static func reconstructed<B: ExactScalarAdmission & ~Copyable>(_ residue: UInt64,
        numeratorBound: UInt64, denominatorBound: UInt64, usage: inout B) throws -> ExactRationalCoefficient? {
        // Every scalar remains bounded by this fixed modulus; checked signed
        // recurrences also reject any violated arithmetic invariant explicitly.
        var previous = Int64(prime), remainder = Int64(residue)
        var previousDenominator: Int64 = 0, denominator: Int64 = 1
        while remainder > Int64(numeratorBound) {
            try intersectionAlgebraStep(&usage)
            let ratio = previous / remainder
            let product = ratio.multipliedReportingOverflow(by: denominator)
            let nextDenominator = previousDenominator.subtractingReportingOverflow(product.partialValue)
            guard !product.overflow, !nextDenominator.overflow else {
                throw rationalAlgebraFailure("Modular rational reconstruction overflowed its signed recurrence.")
            }
            let next = previous % remainder
            guard next < remainder else { throw rationalAlgebraFailure("Modular reconstruction lost strict descent.") }
            previous = remainder; remainder = next
            previousDenominator = denominator; denominator = nextDenominator.partialValue
        }
        guard denominator != 0, denominator != Int64.min else { return nil }
        let magnitude = UInt64(denominator < 0 ? -denominator : denominator)
        guard magnitude <= denominatorBound else { return nil }
        var a = UInt64(remainder), b = magnitude
        while b != 0 {
            try intersectionAlgebraStep(&usage)
            let next = a % b; a = b; b = next
        }
        guard a == 1 else { return nil }
        let signedResidue = denominator < 0 && remainder != 0 ? prime - UInt64(remainder) : UInt64(remainder)
        guard try multiplied(residue, magnitude, usage: &usage) == signedResidue else { return nil }
        let numerator = try ExactRationalCoefficient.natural(Int(remainder), usage: &usage)
        let value = try numerator.divided(by: .natural(Int(magnitude), usage: &usage), usage: &usage)
        return denominator < 0 ? value.negated : value
    }

    private static func quotient<B: ExactScalarAdmission & ~Copyable>(_ source: [ExactRationalCoefficient],
        by divisor: [ExactRationalCoefficient], usage: inout B) throws -> [ExactRationalCoefficient]? {
        guard divisor.last == .one, source.count >= divisor.count else { return nil }
        let count = source.count - divisor.count + 1
        try RationalAlgebraStorage.retain(count, of: ExactRationalCoefficient.self, usage: &usage)
        var result = Array(repeating: ExactRationalCoefficient.zero, count: count)
        try RationalAlgebraStorage.retain(source.count, of: ExactRationalCoefficient.self, usage: &usage)
        var remainder = source
        while remainder.count >= divisor.count, let top = remainder.last {
            try intersectionAlgebraStep(&usage)
            let previousCount = remainder.count, shift = previousCount - divisor.count
            result[shift] = top
            for index in divisor.indices {
                try intersectionAlgebraStep(&usage)
                remainder[index + shift] = try remainder[index + shift]
                    .subtracting(top.multiplied(by: divisor[index], usage: &usage), usage: &usage)
            }
            while let last = remainder.last, last.isZero {
                try intersectionAlgebraStep(&usage); remainder.removeLast()
            }
            guard remainder.count < previousCount else {
                throw rationalAlgebraFailure("A factor receipt lost strict exact degree descent.")
            }
        }
        return remainder.isEmpty ? result : nil
    }

    private static func residues<B: ExactScalarAdmission & ~Copyable>(_ coefficients: [ExactRationalCoefficient],
        usage: inout B) throws -> [UInt64]? {
        try RationalAlgebraStorage.retain(coefficients.count, of: UInt64.self, usage: &usage)
        var result: [UInt64] = []; result.reserveCapacity(coefficients.count)
        for coefficient in coefficients {
            try intersectionAlgebraStep(&usage)
            let numerator = try residue(coefficient.canonicalNumeratorWords, usage: &usage)
            let denominator = try residue(coefficient.canonicalDenominatorWords, usage: &usage)
            guard denominator != 0 else { return nil }
            let inverse = denominator == 1 ? 1 : try power(denominator, exponent: prime - 2, usage: &usage)
            let magnitude = try multiplied(numerator, inverse, usage: &usage)
            result.append(coefficient.isNegative && magnitude != 0 ? prime - magnitude : magnitude)
        }
        return result
    }

    private static func residue<B: ExactScalarAdmission & ~Copyable>(_ words: [UInt32], usage: inout B) throws -> UInt64 {
        var result: UInt64 = 0
        for word in words.reversed() {
            try intersectionAlgebraStep(&usage)
            // result <= 65536, so shifting by 32 and adding one source word
            // cannot exceed 2^48 + 2^32 - 1; no magnitude is truncated.
            result = ((result << 32) | UInt64(word)) % prime
        }
        return result
    }

    private static func multiplied<B: ExactScalarAdmission & ~Copyable>(_ first: UInt64, _ second: UInt64,
        usage: inout B) throws -> UInt64 {
        try intersectionAlgebraStep(&usage)
        return (first * second) % prime
    }

    private static func power<B: ExactScalarAdmission & ~Copyable>(_ base: UInt64, exponent: UInt64,
        usage: inout B) throws -> UInt64 {
        var result: UInt64 = 1, factor = base, remaining = exponent
        while remaining != 0 {
            try intersectionAlgebraStep(&usage)
            if remaining & 1 != 0 { result = try multiplied(result, factor, usage: &usage) }
            remaining >>= 1
            if remaining != 0 { factor = try multiplied(factor, factor, usage: &usage) }
        }
        return result
    }
}
