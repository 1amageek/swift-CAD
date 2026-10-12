#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact affine correspondence for finite composition planning, without root search.
struct OriginalFiniteCurveChartRange<F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>
    where F.Source == F.Value {
    let gain: F.Value
    let offset: F.Value
    let lower: F.Value
    let upper: F.Value
    static func prepare<S: Sendable, C: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ law: borrowing OriginalRationalChartReceipt<S,C,F>, field: borrowing F, using admission: inout A
    ) throws -> Self {
        try admission.consumeWork(1); try law.admitProof(using: &admission)
        guard law.support.count == 1, law.polynomials.variableCount == 1,
            law.parameterTransport.numerators.count == 1, law.parameterTransport.denominators.count == 1 else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        let ring = try ExactPolynomialDomain(field: copy field, variableCount: 1, using: &admission)
        let d = try ring.importing(law.parameterTransport.denominators[0], using: &admission)
        guard try !ring.isZero(d, using: &admission) else { throw OriginalSourceIssuanceFailure.invalidChart }
        let quotient = try ring.divided(ring.importing(law.parameterTransport.numerators[0], using: &admission),
            by: d, using: &admission)
        guard try ring.isZero(quotient.remainder, using: &admission) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        var gain = try field.integer(0, using: &admission), offset = gain
        for term in quotient.quotient.terms {
            try admission.consumeWork(1)
            guard term.powers.count == 1 else { throw OriginalSourceIssuanceFailure.invalidChart }
            switch term.powers[0] {
            case 0: offset = try field.importing(term.coefficient, using: &admission)
            case 1: gain = try field.importing(term.coefficient, using: &admission)
            default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
        }
        guard try field.sign(of: gain, using: &admission) != .zero else { throw OriginalSourceIssuanceFailure.invalidChart }
        let a = try field.adding(field.multiplying(gain, field.importing(law.support[0].lower,
            using: &admission), using: &admission), offset, using: &admission)
        let b = try field.adding(field.multiplying(gain, field.importing(law.support[0].upper,
            using: &admission), using: &admission), offset, using: &admission)
        let ascending = try field.compare(a,b,using: &admission) != .greater
        return Self(gain: gain, offset: offset, lower: ascending ? a : b, upper: ascending ? b : a)
    }
}
