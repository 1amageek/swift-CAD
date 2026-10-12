#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Checked variable embedding; it does not solve, fit or normalize a source.
enum OriginalRuledLawImport {
    static func curve<F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,
        A: ExactScalarAdmission & ~Copyable>(_ law: borrowing ExactPolynomial<F>,
        into ring: ExactPolynomialDomain<F>, axis: Int = 0, field: borrowing F, using admission: inout A
    ) throws -> ExactPolynomial<F> where F.Source == F.Value {
        guard law.variableCount == 1, ring.variableCount == 2, axis >= 0, axis < 2 else { throw OriginalSourceIssuanceFailure.invalidChart }
        try admission.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: law.termCount, of: ExactPolynomialTerm<F.Value>.self))
        var terms: [ExactPolynomialTerm<F.Value>] = []; terms.reserveCapacity(law.termCount)
        for index in law.terms.indices {
            try admission.consumeWork(1)
            let term = law.terms[index]
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Int.self))
            terms.append(.init(powers: axis == 0 ? [term.powers[0], 0] : [0, term.powers[0]],
                coefficient: try field.importing(term.coefficient, using: &admission)))
        }
        // Embedding into either axis preserves the certified term order.
        return try ring.polynomial(orderedTerms: terms, using: &admission)
    }
}
