#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Keeps child-local laws and clips through proved affine authored correspondence.
public struct DefaultOriginalTraversalChartIssuer<Source: OriginalTraversalSourceReading,
    ChildSelection: Sendable, Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalCoefficientBoundChartIssuing
    where Field.Source == Field.Value, Source.Coefficient == Field.Value {
    public typealias Selection = OriginalTraversalChartSelection<Source.Child, ChildSelection, Field>
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source, Selection>, field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source, Selection, Field> {
        try issue(source: source, chart: chart, field: field,
            coefficients: DefaultOriginalSourceCoefficientImporter<Field>(), limits: limits, using: &admission)
    }
    public func issue<C: OriginalSourceCoefficientImporting, A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>, chart: borrowing OriginalSourceChart<Source, Selection>,
        field: borrowing Field, coefficients: borrowing C, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source, Selection, Field> where C.Field == Field {
        let coefficients = copy coefficients
        let source = copy source, chart = copy chart, field = copy field
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { usage in
                try Self.compose(source: source, chart: chart, field: field, coefficients: coefficients, limits: limits, using: &usage)
            }
        } catch { throw .init(preserving: error) }
    }
    private static func compose<C: OriginalSourceCoefficientImporting, A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>, chart: borrowing OriginalSourceChart<Source, Selection>,
        field: borrowing Field, coefficients: borrowing C, limits: OriginalSourceIssuanceLimits, using admission: inout OriginalSourceProofAdmission<A>
    ) throws -> OriginalRationalChartReceipt<Source, Selection, Field> where C.Field == Field {
        try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
        guard source.owns(chart), source.original.originalChild.owns(chart.selection.child.chart) else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
        let child = chart.selection.child
        try child.source.require(.init(remainingSourceDepth: limits.remainingSourceDepth - 1))
        try child.admitProof(using: &admission)
        guard child.polynomials.variableCount == 1, child.homogeneous.count == 4, child.support.count == 1,
            child.parameterTransport.numerators.count == 1, child.parameterTransport.denominators.count == 1 else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        let start = try coefficients.importing(source.original.originalStart, into: field, using: &admission)
        let end = try coefficients.importing(source.original.originalEnd, into: field, using: &admission)
        let extent = try field.subtracting(end, start, using: &admission)
        guard try field.sign(of: extent, using: &admission) != .zero else { throw OriginalSourceIssuanceFailure.invalidSource }
        let r = try ExactPolynomialDomain(field: copy field, variableCount: 1, using: &admission)
        let n = try r.importing(child.parameterTransport.numerators[0], using: &admission)
        let d = try r.importing(child.parameterTransport.denominators[0], using: &admission)
        guard try !r.isZero(d, using: &admission) else { throw OriginalSourceIssuanceFailure.invalidChart }
        let division = try r.divided(n, by: d, using: &admission)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Non-affine child correspondence needs
        // an exact domain pullback. The current directed traversal issuer supports
        // affine local coordinates only; a fitted inverse cannot complete this path.
        guard try r.isZero(division.remainder, using: &admission) else {
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
        var gain = try field.integer(0, using: &admission), offset = gain
        for term in division.quotient.terms {
            try admission.consumeWork(1)
            switch term.powers[0] {
            case 0: offset = term.coefficient
            case 1: gain = term.coefficient
            default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
        }
        guard try field.sign(of: gain, using: &admission) != .zero else { throw OriginalSourceIssuanceFailure.invalidChart }
        let first = try field.dividing(field.subtracting(start, offset, using: &admission), gain, using: &admission)
        let last = try field.dividing(field.subtracting(end, offset, using: &admission), gain, using: &admission)
        let ascending = try field.compare(first, last, using: &admission) != .greater
        var lower = try field.importing(child.support[0].lower, using: &admission)
        var upper = try field.importing(child.support[0].upper, using: &admission)
        let lo = ascending ? first : last, hi = ascending ? last : first
        if try field.compare(lo, lower, using: &admission) == .greater { lower = lo }
        if try field.compare(hi, upper, using: &admission) == .less { upper = hi }
        guard try field.compare(lower, upper, using: &admission) != .greater else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
        var laws: [ExactPolynomial<Field>] = []; laws.reserveCapacity(4)
        for law in child.homogeneous { laws.append(try r.importing(law, using: &admission)) }
        let directedN = try r.subtracting(n, r.scaled(d, by: start, using: &admission), using: &admission)
        let directedD = try r.scaled(d, by: extent, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactPolynomial<Field>.self))
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalSourceParameterInterval<Field.Value>.self))
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
            of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
        let result = OriginalRationalChartReceipt(chart: copy chart, field: copy field, polynomials: r,
            homogeneous: laws, support: [.init(lower: lower, upper: upper)],
            parameterTransport: .init(numerators: [directedN], denominators: [directedD]), proofDepth: try admission.depth)
        try admission.checkpoint(); return result
    }
}
