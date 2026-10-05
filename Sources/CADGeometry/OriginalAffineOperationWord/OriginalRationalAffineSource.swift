import CADCore

/// The direct original affine coefficient law, without normalization or binary conversion.
public struct OriginalRationalAffineSource: Hashable, Sendable {
    /// Three rows [A00, A01, A02, Tx, A10, A11, A12, Ty, A20, A21, A22, Tz].
    public let coefficients: [ExactRationalCoefficient]

    /// Retains the caller-admitted immutable original buffer without copying its limbs.
    public init<B: RationalAlgebraAdmitting>(coefficients: [ExactRationalCoefficient], usage: inout B) throws {
        guard coefficients.count == 12 else { throw rationalAlgebraFailure("Original rational affine source requires exactly twelve coefficients.") }
        self.coefficients = coefficients
        try validateOriginalPayload(usage: &usage)
    }
    func validateOriginalPayload<B: RationalAlgebraAdmitting>(usage: inout B) throws {
        guard coefficients.count == 12 else { throw rationalAlgebraFailure("Original rational affine coefficient layout is invalid.") }
        for coefficient in coefficients {
            try usage.consumeExactWork(1)
            for _ in coefficient.canonicalNumeratorWords { try usage.consumeExactWork(1) }
            for _ in coefficient.canonicalDenominatorWords { try usage.consumeExactWork(1) }
        }
    }
    public func hash(into hasher: inout Hasher) {
        for coefficient in coefficients {
            hasher.combine(coefficient.canonicalSign)
            hasher.combine(coefficient.canonicalNumeratorWords)
            hasher.combine(coefficient.canonicalDenominatorWords)
        }
    }
}
