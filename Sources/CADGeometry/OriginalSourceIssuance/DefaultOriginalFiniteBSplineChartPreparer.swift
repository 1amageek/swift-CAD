#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Source validation belongs to the retained snapshot provider; issuance proves each law.
public struct DefaultOriginalFiniteBSplineChartPreparer<Source: OriginalBSplineSourceReading>: OriginalFiniteBSplineChartPreparing {
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>, field: borrowing OriginalExactScalarDomain,
        maximumCharts: Int, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteBSplineCharts<Source> {
        do {
            try admission.checkpoint(); try source.require(limits)
            let original = source.original, n = original.parameterCount
            guard (1...2).contains(n), maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: [Int].self))
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n,
                of: OriginalSourceParameterInterval<OriginalExactScalar>.self))
            var spans: [[Int]] = []; spans.reserveCapacity(n)
            var support: [OriginalSourceParameterInterval<OriginalExactScalar>] = []; support.reserveCapacity(n)
            var count = 1
            for axis in 0..<n {
                try admission.consumeWork(1)
                // The existing periodic issuer/cover remains a separate capability.
                guard !original.isPeriodic(in: axis) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                let degree = original.degree(in: axis), controls = original.controlCount(in: axis)
                guard degree >= 0, controls > degree else { throw OriginalSourceIssuanceFailure.invalidSource }
                support.append(.init(lower: try field.binary64(exactly: original.knot(at: degree, in: axis), using: &admission),
                    upper: try field.binary64(exactly: original.knot(at: controls, in: axis), using: &admission)))
                var positive = 0
                for index in degree..<controls {
                    try admission.consumeWork(1)
                    if original.knot(at: index, in: axis) < original.knot(at: index + 1, in: axis) { positive += 1 }
                }
                guard positive > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: positive, of: Int.self))
                var selected: [Int] = []; selected.reserveCapacity(positive)
                for index in degree..<controls {
                    try admission.consumeWork(1)
                    if original.knot(at: index, in: axis) < original.knot(at: index + 1, in: axis) { selected.append(index) }
                }
                spans.append(selected)
                let product = count.multipliedReportingOverflow(by: positive)
                guard !product.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                count = product.partialValue
                guard count <= maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
            }
            typealias Law = OriginalRationalChartReceipt<Source, OriginalBSplineChartSelection, OriginalExactScalarDomain>
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Law.self))
            var laws: [Law] = []; laws.reserveCapacity(count)
            let issuer = DefaultOriginalBSplineChartIssuer<Source, OriginalExactScalarDomain>()
            for first in spans[0] {
                for j in 0..<(n == 2 ? spans[1].count : 1) {
                    try admission.consumeWork(1)
                    try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: Int.self))
                    let selected = n == 1 ? [first] : [first, spans[1][j]]
                    let chart = try source.chart(OriginalBSplineChartSelection(spans: selected), limits: limits, using: &admission)
                    laws.append(try issuer.issue(source: source, chart: chart, field: field, limits: limits, using: &admission))
                }
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalFiniteBSplineCharts<Source>.self))
            let result = OriginalFiniteBSplineCharts(source: copy source, field: copy field, support: support, laws: laws)
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
