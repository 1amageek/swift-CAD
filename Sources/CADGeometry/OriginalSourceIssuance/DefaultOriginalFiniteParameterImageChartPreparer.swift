#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Parent issuance transforms each child law once; complete coverage is proved separately.
public struct DefaultOriginalFiniteParameterImageChartPreparer<Source: OriginalParameterImageSourceReading, ChildSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalFiniteParameterImageChartPreparing
    where Field.Source == Field.Value {
    public typealias Selection = OriginalParameterImageChartSelection<Source.Child, ChildSelection, Field>
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        children: borrowing [OriginalRationalChartReceipt<Source.Child, ChildSelection, Field>],
        field: borrowing Field, maximumCharts: Int, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>] {
        do {
            try admission.checkpoint(); try source.require(limits)
            guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
            guard children.count <= maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: children.count,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            var result: [OriginalRationalChartReceipt<Source, Selection, Field>] = []; result.reserveCapacity(children.count)
            let issuer = DefaultOriginalParameterImageChartIssuer<Source, ChildSelection, Field>()
            for index in children.indices {
                try admission.consumeWork(1)
                let chart = try source.chart(Selection(child: children[index]), limits: limits, using: &admission)
                result.append(try issuer.issue(source: source, chart: chart, field: field, limits: limits, using: &admission))
            }
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
