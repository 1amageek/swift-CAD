import CADCore

/// Exact canonical rational transfer into a caller-selected coefficient field.
enum OriginalSourceRationalImport {
    static func value<F: ExactScalarArithmetic & ExactScalarOrdering,
        A: ExactScalarAdmission & ~Copyable>(_ value: borrowing ExactRationalCoefficient,
        field: borrowing F, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> F.Value {
        do {
            try admission.checkpoint()
            let base = try field.integer(UInt64(1) << 32, using: &admission)
            var numerator = try field.integer(0, using: &admission)
            for word in value.canonicalNumeratorWords.reversed() {
                try admission.consumeWork(1)
                numerator = try field.adding(field.multiplying(numerator, base, using: &admission),
                    field.integer(word, using: &admission), using: &admission)
            }
            var denominator = try field.integer(0, using: &admission)
            for word in value.canonicalDenominatorWords.reversed() {
                try admission.consumeWork(1)
                denominator = try field.adding(field.multiplying(denominator, base, using: &admission),
                    field.integer(word, using: &admission), using: &admission)
            }
            if value.canonicalSign < 0 { numerator = try field.negated(numerator, using: &admission) }
            let result = try field.dividing(numerator, denominator, using: &admission)
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
