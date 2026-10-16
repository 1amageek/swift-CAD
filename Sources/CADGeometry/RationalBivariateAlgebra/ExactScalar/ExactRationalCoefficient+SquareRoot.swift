/// Exact nonnegative rational square root, never a rounded root candidate.
extension ExactRationalCoefficient {
    package func exactSquareRoot<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> Self? {
        if isNegative { return nil }
        if isZero { return .zero }
        func root(_ original: ExactNaturalMagnitude, usage: inout B) throws -> ExactNaturalMagnitude? {
            let bits = try original.admittedBitCount(usage: &usage)
            var candidate = ExactNaturalMagnitude.zero
            let rootBits = bits / 2 + bits % 2
            for bit in (0..<rootBits).reversed() {
                try usage.consumeWork(1)
                let next = try candidate.adding(.one.shifted(by: bit, usage: &usage), usage: &usage)
                let square = try next.multiplied(by: next, usage: &usage)
                try usage.consumeWork(max(square.words.count, original.words.count))
                if square.compared(to: original) <= 0 { candidate = next }
            }
            let square = try candidate.multiplied(by: candidate, usage: &usage)
            try usage.consumeWork(max(square.words.count, original.words.count))
            return square == original ? candidate : nil
        }
        guard let n = try root(numerator, usage: &usage),
            let d = try root(denominator, usage: &usage) else { return nil }
        return try Self(canonicalSign: 1, numeratorWords: n.words, denominatorWords: d.words, usage: &usage)
    }
}
