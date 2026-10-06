/// Exact rational real root recognition from reduced original integer limbs.
extension ExactRationalCoefficient {
    package func exactRealRoot<B: RationalAlgebraAdmitting>(degree: Int,
        usage: inout B) throws -> Self? {
        guard degree > 0 else { throw rationalAlgebraFailure("An exact rational root needs a positive original degree.") }
        if isNegative, degree % 2 == 0 { return nil }
        if isZero { return .zero }
        func root(_ original: ExactNaturalMagnitude, usage: inout B) throws -> ExactNaturalMagnitude? {
            if original == .one { try usage.consumeExactWork(1); return .one }
            let bits = try original.admittedBitCount(usage: &usage)
            // Every integer root >=2 has degree+1 or more source bits.
            if degree >= bits { return nil }
            func power(_ value: ExactNaturalMagnitude, usage: inout B) throws -> ExactNaturalMagnitude {
                var count = degree, factor = value, result = ExactNaturalMagnitude.one
                while count > 0 {
                    try usage.consumeExactWork(1)
                    if count % 2 == 1 { result = try result.multiplied(by: factor, usage: &usage) }
                    count /= 2
                    if count > 0 { factor = try factor.multiplied(by: factor, usage: &usage) }
                }
                return result
            }
            var candidate = ExactNaturalMagnitude.zero
            let rootBits = bits / degree + (bits % degree == 0 ? 0 : 1)
            for bit in (0..<rootBits).reversed() {
                try usage.consumeExactWork(1)
                let next = try candidate.adding(.one.shifted(by: bit, usage: &usage), usage: &usage)
                let value = try power(next, usage: &usage)
                try usage.consumeExactWork(max(value.words.count, original.words.count))
                if value.compared(to: original) <= 0 { candidate = next }
            }
            let value = try power(candidate, usage: &usage)
            try usage.consumeExactWork(max(value.words.count, original.words.count))
            return value == original ? candidate : nil
        }
        guard let n = try root(numerator, usage: &usage),
              let d = try root(denominator, usage: &usage) else { return nil }
        return try Self(canonicalSign: isNegative ? -1 : 1,
            numeratorWords: n.words, denominatorWords: d.words, usage: &usage)
    }
}
