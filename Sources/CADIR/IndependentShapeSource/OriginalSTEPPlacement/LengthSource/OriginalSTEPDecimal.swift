import CADCore
import CADGeometry

/// Exact mathematical value of an original STEP decimal token.
public enum OriginalSTEPDecimal {
    public static func coefficient<B: RationalAlgebraAdmitting>(_ literal: String, usage: inout B) throws -> ExactRationalCoefficient {
        try usage.consumeExactWork(literal.utf8.count)
        var iterator = literal.utf8.makeIterator()
        var next = iterator.next()
        var negative = false
        if next == 43 || next == 45 { negative = next == 45; next = iterator.next() }
        let ten = try ExactRationalCoefficient.originalDouble(10, usage: &usage)
        var value = ExactRationalCoefficient.zero
        var digits = 0, fractional = 0
        var dot = false
        while let byte = next {
            if byte == 46 {
                guard !dot else { throw invalid() }
                dot = true; next = iterator.next(); continue
            }
            guard byte >= 48, byte <= 57 else { break }
            let digit = try ExactRationalCoefficient.originalDouble(Double(byte - 48), usage: &usage)
            value = try value.multiplied(by: ten, usage: &usage).adding(digit, usage: &usage)
            digits += 1; if dot { fractional += 1 }
            next = iterator.next()
        }
        guard digits > 0 else { throw invalid() }
        var exponent = 0
        if let byte = next {
            guard byte == 69 || byte == 101 else { throw invalid() }
            next = iterator.next()
            var negativeExponent = false
            if next == 43 || next == 45 { negativeExponent = next == 45; next = iterator.next() }
            var exponentDigits = 0
            while let byte = next {
                guard byte >= 48, byte <= 57 else { throw invalid() }
                let product = exponent.multipliedReportingOverflow(by: 10)
                let sum = product.partialValue.addingReportingOverflow(Int(byte - 48))
                guard !product.overflow, !sum.overflow else {
                    throw IndependentShapeSourceError.resourceLimitExceeded("Original decimal exponent exceeds the integer admission domain.")
                }
                exponent = sum.partialValue; exponentDigits += 1; next = iterator.next()
            }
            guard exponentDigits > 0 else { throw invalid() }
            if negativeExponent { exponent = -exponent }
        }
        let adjusted = exponent.subtractingReportingOverflow(fractional)
        guard !adjusted.overflow, adjusted.partialValue != Int.min else {
            throw IndependentShapeSourceError.resourceLimitExceeded("Original decimal exponent arithmetic overflows.")
        }
        let gain = try powerOfTen(adjusted.partialValue, usage: &usage)
        let result = try value.multiplied(by: gain, usage: &usage)
        return negative ? result.negated : result
    }
    public static func powerOfTen<B: RationalAlgebraAdmitting>(_ exponent: Int, usage: inout B) throws -> ExactRationalCoefficient {
        guard exponent != Int.min else { throw IndependentShapeSourceError.resourceLimitExceeded("Original decimal exponent overflows.") }
        var remaining = abs(exponent)
        var factor = try ExactRationalCoefficient.originalDouble(10, usage: &usage)
        var result = ExactRationalCoefficient.one
        while remaining > 0 {
            try usage.consumeExactWork(1)
            if remaining & 1 == 1 { result = try result.multiplied(by: factor, usage: &usage) }
            remaining >>= 1
            if remaining > 0 { factor = try factor.multiplied(by: factor, usage: &usage) }
        }
        return exponent < 0 ? try ExactRationalCoefficient.one.divided(by: result, usage: &usage) : result
    }
    private static func invalid() -> IndependentShapeSourceError { .invalidSource("Malformed original STEP decimal token.") }
}
