#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Normalizes only proved affine original correspondence and preserves its guard.
struct OriginalCoonsBoundaryLaw<F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>
    where F.Source == F.Value {
    let homogeneous: [ExactPolynomial<F>]
    let support: OriginalSourceParameterInterval<F.Value>
    let start: [F.Value]
    let end: [F.Value]
    static func prepare<S: Sendable, C: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ selection: borrowing OriginalCoonsBoundarySelection<S, C, F>,
        source: borrowing OriginalSourceBinding<S>, axis: Int, ring: ExactPolynomialDomain<F>,
        field: borrowing F, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws -> Self {
        try source.require(limits)
        guard source.owns(selection.curve.chart), source.owns(selection.start.curve.chart),
            source.owns(selection.end.curve.chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
        let curve = selection.curve
        guard curve.polynomials.variableCount == 1, curve.support.count == 1, curve.homogeneous.count == 4,
            curve.parameterTransport.numerators.count == 1, curve.parameterTransport.denominators.count == 1,
            selection.start.position.count == 3, selection.end.position.count == 3 else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        try curve.admitProof(using: &admission)
        let zero = try field.integer(0, using: &admission), one = try field.integer(1, using: &admission)
        for endpointIndex in 0..<2 {
            let endpoint = endpointIndex == 0 ? selection.start : selection.end
            try admission.admitDepth(value: endpoint.depth.value, coefficient: endpoint.depth.coefficient)
            guard try field.compare(field.importing(endpoint.originalParameter, using: &admission),
                endpointIndex == 0 ? zero : one, using: &admission) == .equal else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
        }
        let unary = try ExactPolynomialDomain(field: copy field, variableCount: 1, using: &admission)
        let n = try unary.importing(curve.parameterTransport.numerators[0], using: &admission)
        let d = try unary.importing(curve.parameterTransport.denominators[0], using: &admission)
        guard try !unary.isZero(d, using: &admission) else { throw OriginalSourceIssuanceFailure.invalidChart }
        let quotient = try unary.divided(n, by: d, using: &admission)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Non-affine original parameter images need
        // their genuine source-law pullback. DefaultOriginalCoonsChartIssuer currently
        // calls this affine constructor; whole-family completion requires that pullback
        // and exact domain/denominator correspondence rather than a fitted inverse.
        guard try unary.isZero(quotient.remainder, using: &admission) else {
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
        var gain = zero, offset = zero
        for term in quotient.quotient.terms {
            try admission.consumeWork(1)
            switch term.powers[0] {
            case 0: offset = try field.importing(term.coefficient, using: &admission)
            case 1: gain = try field.importing(term.coefficient, using: &admission)
            default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
        }
        guard try field.sign(of: gain, using: &admission) != .zero else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        let variable = try ring.variable(axis, using: &admission)
        let inverse = try ring.scaled(ring.subtracting(variable,
            ring.constant(offset, using: &admission), using: &admission),
            by: field.dividing(one, gain, using: &admission), using: &admission)
        let other = try ring.variable(1 - axis, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactPolynomial<F>.self))
        let replacements = axis == 0 ? [inverse, other] : [other, inverse]
        let guardLaw = try ring.substituted(OriginalRuledLawImport.curve(d, into: ring,
            axis: axis, field: field, using: &admission), with: replacements, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<F>.self))
        var laws: [ExactPolynomial<F>] = []; laws.reserveCapacity(4)
        for index in 0..<4 {
            let imported = try OriginalRuledLawImport.curve(curve.homogeneous[index], into: ring,
                axis: axis, field: field, using: &admission)
            laws.append(try ring.multiplying(ring.substituted(imported, with: replacements, using: &admission),
                guardLaw, using: &admission))
        }
        let a = try field.adding(field.multiplying(gain, field.importing(curve.support[0].lower,
            using: &admission), using: &admission), offset, using: &admission)
        let b = try field.adding(field.multiplying(gain, field.importing(curve.support[0].upper,
            using: &admission), using: &admission), offset, using: &admission)
        let ascending = try field.compare(a, b, using: &admission) != .greater
        let lower = ascending ? a : b, upper = ascending ? b : a
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: F.Value.self))
        var start: [F.Value] = [], end: [F.Value] = []; start.reserveCapacity(3); end.reserveCapacity(3)
        for index in 0..<3 {
            start.append(try field.importing(selection.start.position[index], using: &admission))
            end.append(try field.importing(selection.end.position[index], using: &admission))
        }
        return Self(homogeneous: laws, support: .init(lower: lower, upper: upper), start: start, end: end)
    }
}
