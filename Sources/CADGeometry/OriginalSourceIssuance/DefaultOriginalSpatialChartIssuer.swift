#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Applies an authored spatial action without rebuilding child source laws.
public struct DefaultOriginalSpatialChartIssuer<Source: OriginalSpatialSourceReading,
    ChildSelection: Sendable, Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:
    OriginalCoefficientBoundChartIssuing where Field.Source == Field.Value, Source.Coefficient == Field.Source {
    public typealias Selection = OriginalSpatialChartSelection<Source.Child, ChildSelection, Field>
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
        let source=copy source,chart=copy chart,field=copy field,coefficients=copy coefficients
        do {
            return try admission.withProofScope { admission in
                try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
                guard source.owns(chart), source.original.originalChild.owns(chart.selection.child.chart) else {
                    throw OriginalSourceIssuanceFailure.foreignBinding
                }
                guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                try chart.selection.child.source.require(.init(remainingSourceDepth: limits.remainingSourceDepth - 1))
                try chart.selection.child.admitProof(using: &admission)
                let child = chart.selection.child
                guard child.homogeneous.count == 4, child.support.count == child.polynomials.variableCount,
                    child.parameterTransport.numerators.count == child.support.count,
                    child.parameterTransport.denominators.count == child.support.count else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                // Checked imports retain the caller's field authority. Equal numeric
                // approximations never authorize a foreign coefficient context.
                let ring = try ExactPolynomialDomain(field: copy field,
                    variableCount: child.polynomials.variableCount, using: &admission)
                let output=try OriginalSpatialPositionTransport.applying(source:source.original,
                    homogeneous:child.homogeneous,ring:ring,coefficients:coefficients,using:&admission)
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: child.support.count,
                    of: OriginalSourceParameterInterval<Field.Value>.self))
                var support: [OriginalSourceParameterInterval<Field.Value>] = []; support.reserveCapacity(child.support.count)
                let transportCount = child.support.count.multipliedReportingOverflow(by: 2)
                guard !transportCount.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: transportCount.partialValue, of: ExactPolynomial<Field>.self))
                var numerator: [ExactPolynomial<Field>] = [], denominator: [ExactPolynomial<Field>] = []
                numerator.reserveCapacity(child.support.count); denominator.reserveCapacity(child.support.count)
                for axis in child.support.indices {
                    try admission.consumeWork(1)
                    support.append(.init(lower: try field.importing(child.support[axis].lower, using: &admission),
                        upper: try field.importing(child.support[axis].upper, using: &admission)))
                    numerator.append(try ring.importing(child.parameterTransport.numerators[axis], using: &admission))
                    denominator.append(try ring.importing(child.parameterTransport.denominators[axis], using: &admission))
                }
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                    of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
                let result = OriginalRationalChartReceipt(chart: copy chart, field: copy field,
                    polynomials: ring, homogeneous: output, support: support,
                    parameterTransport: .init(numerators: numerator, denominators: denominator), proofDepth: try admission.depth)
                try admission.checkpoint(); return result
            }
        } catch { throw .init(preserving: error) }
    }
}
