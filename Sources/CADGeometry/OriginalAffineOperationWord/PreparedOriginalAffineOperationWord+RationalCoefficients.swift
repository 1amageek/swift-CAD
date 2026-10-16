import CADCore

extension PreparedOriginalAffineOperationWord {
    /// Retains the exact rational action for a format's coefficient publication.
    /// Algebraic coefficients cannot be replaced by rounded or interval values.
    public func exactRationalCoefficients<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws
        -> [ExactRationalCoefficient] {
        try usage.consumeWork(1)
        guard source.isRational, source.coefficients.count == 12 else {
            throw rationalAlgebraFailure("Original affine publication requires an exact rational action.")
        }
        try OriginalAffineRationalMatrix.retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        for value in source.coefficients {
            try usage.consumeWork(1)
            for _ in value.canonicalNumeratorWords { try usage.consumeWork(1) }
            for _ in value.canonicalDenominatorWords { try usage.consumeWork(1) }
        }
        // Immutable cache limbs are shared; the admitted returned value retains
        // their owner for its lifetime. Foreign lexical conversion is downstream.
        return source.coefficients
    }
}
