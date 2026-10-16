import CADCore

/// Reuses the source-owned whole-chart theorem and checked auxiliary reduction.
public struct DefaultOriginalPolynomialNativeLiftChartIssuer: OriginalPolynomialNativeLiftChartIssuing {
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(
        family: borrowing OriginalFiniteNativeSurfaceLiftGraphs<OriginalNativeSurfaceLiftSnapshot>,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<
        OriginalNativeSurfaceLiftSnapshot, OriginalPolynomialNativeLiftChart, OriginalExactScalarDomain> {
        let family = copy family
        do {
            return try admission.withProofScope { a in
                try a.checkpoint()
                try family.admitProof(limits: limits, using: &a)
                let native = family.source.original.originalSurface.original
                // FIXME(INCOMPLETE_IMPLEMENTATION): Rational ruled child composition
                // currently consumes a single whole nonperiodic Native lift chart.
                // Multiple/periodic chart families need a retained guarded child atlas
                // before this bridge can claim general lift/ruled coverage.
                guard !native.isUPeriodic, !native.isVPeriodic,
                    family.surface.laws.count == 1, family.pcurve.laws.count == 1,
                    family.graphs.count == 1 else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                let f = family.field
                // One sealed complete chart must cover the authored support itself.
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    let bound = family.surface.support[axis]
                    let chart = family.surface.laws[0].support[axis]
                    guard try f.compare(bound.lower, chart.lower, using: &a) == .equal,
                        try f.compare(bound.upper, chart.upper, using: &a) == .equal else {
                        throw OriginalSourceIssuanceFailure.invalidChart
                    }
                }
                let p = family.pcurve.support[0], q = family.pcurve.laws[0].support[0]
                guard try f.compare(p.lower, q.lower, using: &a) == .equal,
                    try f.compare(p.upper, q.upper, using: &a) == .equal else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                let reduction = try DefaultOriginalPolynomialSurfaceLiftGraphReducer<OriginalNativeSurfaceLiftSnapshot>()
                    .reduce(family.graphs[0], limits: limits, using: &a)
                let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
                guard reduction.graph.support.count == 1,
                    try f.compare(reduction.graph.support[0].lower, zero, using: &a) == .equal,
                    try f.compare(reduction.graph.support[0].upper, one, using: &a) == .equal else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalPolynomialNativeLiftChart.self))
                let chart = try family.source.chart(OriginalPolynomialNativeLiftChart(family: family, reduction: reduction),
                    limits: limits, using: &a)
                typealias Law = OriginalRationalChartReceipt<OriginalNativeSurfaceLiftSnapshot,
                    OriginalPolynomialNativeLiftChart, OriginalExactScalarDomain>
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Law.self))
                let result = Law(chart: chart, field: f, polynomials: reduction.graph.polynomials,
                    homogeneous: reduction.graph.homogeneous, support: reduction.graph.support,
                    parameterTransport: reduction.graph.parameterTransport, proofDepth: try a.depth)
                try a.checkpoint()
                return result
            }
        } catch { throw .init(preserving: error) }
    }
}
