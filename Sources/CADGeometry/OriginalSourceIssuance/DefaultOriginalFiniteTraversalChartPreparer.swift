#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Selects all child charts intersecting the exact directed station interval.
public struct DefaultOriginalFiniteTraversalChartPreparer<Source: OriginalTraversalSourceReading, ChildSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalFiniteTraversalChartPreparing
    where Field.Source == Field.Value, Source.Coefficient == Field.Value {
    public typealias Selection = OriginalTraversalChartSelection<Source.Child, ChildSelection, Field>
    public init() {}
    public func prepare<C: OriginalSourceCoefficientImporting, A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>,
        children: borrowing [OriginalRationalChartReceipt<Source.Child, ChildSelection, Field>],
        field: borrowing Field, coefficients: borrowing C, maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>] where C.Field == Field {
        do {
            try admission.checkpoint(); try source.require(limits)
            guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
            let start = try coefficients.importing(source.original.originalStart, into: field, using: &admission)
            let end = try coefficients.importing(source.original.originalEnd, into: field, using: &admission)
            let order = try field.compare(start,end,using: &admission)
            guard order != .equal else { throw OriginalSourceIssuanceFailure.invalidSource }
            let lower = order == .less ? start : end, upper = order == .less ? end : start
            // Retain only indices; original law payloads remain shared with their owner.
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: min(children.count, maximumCharts), of: Int.self))
            var selected: [Int] = []; selected.reserveCapacity(min(children.count, maximumCharts))
            for index in children.indices {
                guard source.original.originalChild.owns(children[index].chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let range = try OriginalFiniteCurveChartRange<Field>.prepare(children[index], field: field, using: &admission)
                if try field.compare(range.upper, lower, using: &admission) != .less,
                    try field.compare(range.lower, upper, using: &admission) != .greater {
                    guard selected.count < maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                    selected.append(index)
                }
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: selected.count,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            var result: [OriginalRationalChartReceipt<Source, Selection, Field>] = []; result.reserveCapacity(selected.count)
            let issuer = DefaultOriginalTraversalChartIssuer<Source, ChildSelection, Field>()
            for index in selected {
                let chart = try source.chart(Selection(child: children[index]), limits: limits, using: &admission)
                result.append(try issuer.issue(source: source, chart: chart, field: field, coefficients: coefficients,
                    limits: limits, using: &admission))
            }
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
