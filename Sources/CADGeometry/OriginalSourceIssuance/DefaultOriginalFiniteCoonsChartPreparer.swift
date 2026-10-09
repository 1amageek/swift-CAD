#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Counts compatible U/V combinations before issuing any parent law.
public struct DefaultOriginalFiniteCoonsChartPreparer<Source: OriginalCoonsSourceReading,
    BottomSelection: Sendable, TopSelection: Sendable, LeftSelection: Sendable, RightSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalFiniteCoonsChartPreparing
    where Field.Source == Field.Value {
    public typealias Selection = OriginalCoonsChartSelection<Source.Bottom, BottomSelection, Source.Top, TopSelection,
        Source.Left, LeftSelection, Source.Right, RightSelection, Field>
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        bottom: borrowing [OriginalCoonsBoundarySelection<Source.Bottom, BottomSelection, Field>],
        top: borrowing [OriginalCoonsBoundarySelection<Source.Top, TopSelection, Field>],
        left: borrowing [OriginalCoonsBoundarySelection<Source.Left, LeftSelection, Field>],
        right: borrowing [OriginalCoonsBoundarySelection<Source.Right, RightSelection, Field>],
        field: borrowing Field, maximumCharts: Int, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>] {
        do {
            try admission.checkpoint(); try source.require(limits)
            guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
            let b = try ranges(bottom, source: source.original.bottomBoundary, field: field, using: &admission)
            let t = try ranges(top, source: source.original.topBoundary, field: field, using: &admission)
            let l = try ranges(left, source: source.original.leftBoundary, field: field, using: &admission)
            let e = try ranges(right, source: source.original.rightBoundary, field: field, using: &admission)
            let zero = try field.integer(0, using: &admission), one = try field.integer(1, using: &admission)
            var count = 0
            for i in b.indices { for j in t.indices {
                if try overlaps(b[i], t[j], lower: zero, upper: one, field: field, using: &admission) {
                    for k in l.indices { for m in e.indices {
                        if try overlaps(l[k], e[m], lower: zero, upper: one, field: field, using: &admission) {
                            let next = count.addingReportingOverflow(1)
                            guard !next.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                            guard next.partialValue <= maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                            count = next.partialValue
                        }
                    } }
                }
            } }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            var result: [OriginalRationalChartReceipt<Source, Selection, Field>] = []; result.reserveCapacity(count)
            let issuer = DefaultOriginalCoonsChartIssuer<Source, BottomSelection, TopSelection, LeftSelection, RightSelection, Field>()
            for i in b.indices { for j in t.indices {
                if try overlaps(b[i], t[j], lower: zero, upper: one, field: field, using: &admission) {
                    for k in l.indices { for m in e.indices {
                        if try overlaps(l[k], e[m], lower: zero, upper: one, field: field, using: &admission) {
                            let selection = Selection(bottom: bottom[i], top: top[j], left: left[k], right: right[m])
                            let chart = try source.chart(selection, limits: limits, using: &admission)
                            result.append(try issuer.issue(source: source, chart: chart, field: field, limits: limits, using: &admission))
                        }
                    } }
                }
            } }
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
    private func ranges<S: Sendable, C: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ boundaries: borrowing [OriginalCoonsBoundarySelection<S, C, Field>], source: borrowing OriginalSourceBinding<S>,
        field: borrowing Field, using admission: inout A
    ) throws -> [OriginalSourceParameterInterval<Field.Value>] {
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: boundaries.count,
            of: OriginalSourceParameterInterval<Field.Value>.self))
        var result: [OriginalSourceParameterInterval<Field.Value>] = []; result.reserveCapacity(boundaries.count)
        for index in boundaries.indices {
            try admission.consumeWork(1)
            let selected = boundaries[index], law = selected.curve
            guard source.owns(law.chart), source.owns(selected.start.curve.chart), source.owns(selected.end.curve.chart) else {
                throw OriginalSourceIssuanceFailure.foreignBinding
            }
            let range = try OriginalFiniteCurveChartRange<Field>.prepare(law, field: field, using: &admission)
            try admission.admitDepth(value: selected.start.depth.value, coefficient: selected.start.depth.coefficient)
            try admission.admitDepth(value: selected.end.depth.value, coefficient: selected.end.depth.coefficient)
            result.append(.init(lower: range.lower, upper: range.upper))
        }
        return result
    }
    private func overlaps<A: ExactScalarAdmission & ~Copyable>(
        _ first: OriginalSourceParameterInterval<Field.Value>, _ second: OriginalSourceParameterInterval<Field.Value>,
        lower: Field.Value, upper: Field.Value, field: borrowing Field, using admission: inout A
    ) throws -> Bool {
        try admission.consumeWork(1)
        var lo = lower, hi = upper
        for k in 0..<2 {
            let range = k == 0 ? first : second
            if try field.compare(range.lower, lo, using: &admission) == .greater { lo = range.lower }
            if try field.compare(range.upper, hi, using: &admission) == .less { hi = range.upper }
        }
        return try field.compare(lo, hi, using: &admission) != .greater
    }
}
