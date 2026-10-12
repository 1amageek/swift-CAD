#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Parent issuance transforms each child law once; complete coverage is proved separately.
public struct DefaultOriginalFiniteSpatialChartPreparer<Source: OriginalSpatialSourceReading, ChildSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalFiniteSpatialChartPreparing
    where Field.Source == Field.Value, Source.Coefficient == Field.Value {
    public typealias Selection = OriginalSpatialChartSelection<Source.Child, ChildSelection, Field>
    public init() {}
    public func prepare<C: OriginalSourceCoefficientImporting, A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        children: borrowing [OriginalRationalChartReceipt<Source.Child, ChildSelection, Field>],
        field: borrowing Field, coefficients: borrowing C, maximumCharts: Int, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>] where C.Field == Field {
        do {
            try admission.checkpoint(); try source.require(limits)
            guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
            guard children.count <= maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: children.count,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            var result: [OriginalRationalChartReceipt<Source, Selection, Field>] = []; result.reserveCapacity(children.count)
            let issuer = DefaultOriginalSpatialChartIssuer<Source, ChildSelection, Field>()
            for index in children.indices {
                try admission.consumeWork(1)
                let chart = try source.chart(Selection(child: children[index]), limits: limits, using: &admission)
                result.append(try issuer.issue(source: source, chart: chart, field: field, coefficients: coefficients, limits: limits, using: &admission))
            }
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
