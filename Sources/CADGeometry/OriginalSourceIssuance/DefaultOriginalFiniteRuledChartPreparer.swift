#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Keeps both closed chart owners at joins; the domain issuer proves the final cover.
public struct DefaultOriginalFiniteRuledChartPreparer<Source: OriginalRuledSourceReading,
    FirstSelection: Sendable, SecondSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalFiniteRuledChartPreparing
    where Field.Source == Field.Value {
    public typealias Selection = OriginalRuledChartSelection<Source.First, FirstSelection, Source.Second, SecondSelection, Field>
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        first: borrowing [OriginalRationalChartReceipt<Source.First, FirstSelection, Field>],
        second: borrowing [OriginalRationalChartReceipt<Source.Second, SecondSelection, Field>],
        field: borrowing Field, maximumCharts: Int, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>] {
        do {
            try admission.checkpoint(); try source.require(limits)
            guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
            let lower = try field.binary64(exactly: source.original.originalLowerU, using: &admission)
            let upper = try field.binary64(exactly: source.original.originalUpperU, using: &admission)
            guard try field.compare(lower, upper, using: &admission) == .less else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            for i in first.indices {
                try admission.consumeWork(1)
                guard source.original.firstBoundary.owns(first[i].chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
            }
            for j in second.indices {
                try admission.consumeWork(1)
                guard source.original.secondBoundary.owns(second[j].chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
            }
            // Count before reserving output so allocator growth cannot bypass admission.
            var count = 0
            for i in first.indices {
                for j in second.indices {
                    if try overlaps(first[i], second[j], lower: lower, upper: upper, field: field, using: &admission) {
                        let next = count.addingReportingOverflow(1)
                        guard !next.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                        guard next.partialValue <= maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                        count = next.partialValue
                    }
                }
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            var result: [OriginalRationalChartReceipt<Source, Selection, Field>] = []; result.reserveCapacity(count)
            let issuer = DefaultOriginalRuledChartIssuer<Source, FirstSelection, SecondSelection, Field>()
            for i in first.indices {
                for j in second.indices {
                    if try overlaps(first[i], second[j], lower: lower, upper: upper, field: field, using: &admission) {
                        let chart = try source.chart(Selection(first: first[i], second: second[j]), limits: limits, using: &admission)
                        result.append(try issuer.issue(source: source, chart: chart, field: field, limits: limits, using: &admission))
                    }
                }
            }
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
    private func overlaps<A: ExactScalarAdmission & ~Copyable>(
        _ first: borrowing OriginalRationalChartReceipt<Source.First, FirstSelection, Field>,
        _ second: borrowing OriginalRationalChartReceipt<Source.Second, SecondSelection, Field>,
        lower: Field.Value, upper: Field.Value, field: borrowing Field, using admission: inout A
    ) throws -> Bool {
        try admission.consumeWork(1); try first.admitProof(using: &admission); try second.admitProof(using: &admission)
        guard first.support.count == 1, second.support.count == 1 else { throw OriginalSourceIssuanceFailure.invalidChart }
        var lo = lower, hi = upper
        for k in 0..<2 {
            let range = k == 0 ? first.support[0] : second.support[0]
            let a = try field.importing(range.lower, using: &admission), b = try field.importing(range.upper, using: &admission)
            if try field.compare(a, lo, using: &admission) == .greater { lo = a }
            if try field.compare(b, hi, using: &admission) == .less { hi = b }
        }
        return try field.compare(lo, hi, using: &admission) != .greater
    }
}
