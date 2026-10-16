#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Composes the original four-boundary law and verifies every exact corner pair.
public struct DefaultOriginalCoonsChartIssuer<Source: OriginalCoonsSourceReading,
    BottomSelection: Sendable, TopSelection: Sendable, LeftSelection: Sendable, RightSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalRationalChartIssuing
    where Field.Source == Field.Value {
    public typealias Selection = OriginalCoonsChartSelection<Source.Bottom, BottomSelection,
        Source.Top, TopSelection, Source.Left, LeftSelection, Source.Right, RightSelection, Field>
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source, Selection>, field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source, Selection, Field> {
        let source = copy source, chart = copy chart, field = copy field
        do {
            return try admission.withProofScope { usage in
                try Self.compose(source: source, chart: chart, field: field, limits: limits, using: &usage)
            }
        } catch { throw .init(preserving: error) }
    }
    private static func compose<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>, chart: borrowing OriginalSourceChart<Source, Selection>,
        field: borrowing Field, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws -> OriginalRationalChartReceipt<Source, Selection, Field> {
        try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
        guard source.owns(chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
        guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
        let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
        let r = try ExactPolynomialDomain(field: copy field, variableCount: 2, using: &admission)
        let b = try OriginalCoonsBoundaryLaw.prepare(chart.selection.bottom, source: source.original.bottomBoundary,
            axis: 0, ring: r, field: field, limits: children, using: &admission)
        let t = try OriginalCoonsBoundaryLaw.prepare(chart.selection.top, source: source.original.topBoundary,
            axis: 0, ring: r, field: field, limits: children, using: &admission)
        let l = try OriginalCoonsBoundaryLaw.prepare(chart.selection.left, source: source.original.leftBoundary,
            axis: 1, ring: r, field: field, limits: children, using: &admission)
        let e = try OriginalCoonsBoundaryLaw.prepare(chart.selection.right, source: source.original.rightBoundary,
            axis: 1, ring: r, field: field, limits: children, using: &admission)
        for axis in 0..<3 {
            try admission.consumeWork(4)
            guard try field.compare(b.start[axis], l.start[axis], using: &admission) == .equal,
                try field.compare(b.end[axis], e.start[axis], using: &admission) == .equal,
                try field.compare(t.start[axis], l.end[axis], using: &admission) == .equal,
                try field.compare(t.end[axis], e.end[axis], using: &admission) == .equal else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
        }
        let zero = try field.integer(0, using: &admission), one = try field.integer(1, using: &admission)
        func intersection(_ a: OriginalSourceParameterInterval<Field.Value>,
            _ b: OriginalSourceParameterInterval<Field.Value>, _ usage: inout A
        ) throws -> OriginalSourceParameterInterval<Field.Value> {
            var lower = zero, upper = one
            for index in 0..<2 {
                let range = index == 0 ? a : b
                try usage.consumeWork(1)
                if try field.compare(range.lower, lower, using: &usage) == .greater { lower = range.lower }
                if try field.compare(range.upper, upper, using: &usage) == .less { upper = range.upper }
            }
            guard try field.compare(lower, upper, using: &usage) != .greater else { throw OriginalSourceIssuanceFailure.invalidChart }
            return .init(lower: lower, upper: upper)
        }
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalSourceParameterInterval<Field.Value>.self))
        let support = [try intersection(b.support, t.support, &admission), try intersection(l.support, e.support, &admission)]
        let u = try r.variable(0, using: &admission), v = try r.variable(1, using: &admission)
        let unit = try r.constant(one, using: &admission)
        let um = try r.subtracting(unit, u, using: &admission), vm = try r.subtracting(unit, v, using: &admission)
        // Product guards are preserved; no pair equation or solver is evaluated here.
        let bt = try r.multiplying(b.homogeneous[3], t.homogeneous[3], using: &admission)
        let le = try r.multiplying(l.homogeneous[3], e.homogeneous[3], using: &admission)
        let w = try r.multiplying(bt, le, using: &admission)
        guard try !r.isZero(w, using: &admission) else { throw OriginalSourceIssuanceFailure.invalidSource }
        let bw = try r.multiplying(t.homogeneous[3], le, using: &admission)
        let tw = try r.multiplying(b.homogeneous[3], le, using: &admission)
        let lw = try r.multiplying(bt, e.homogeneous[3], using: &admission)
        let ew = try r.multiplying(bt, l.homogeneous[3], using: &admission)
        let c00 = try r.multiplying(um, vm, using: &admission), c10 = try r.multiplying(u, vm, using: &admission)
        let c01 = try r.multiplying(um, v, using: &admission), c11 = try r.multiplying(u, v, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
        var laws: [ExactPolynomial<Field>] = []; laws.reserveCapacity(4)
        for axis in 0..<3 {
            let a = try r.multiplying(r.multiplying(b.homogeneous[axis], bw, using: &admission), vm, using: &admission)
            let c = try r.multiplying(r.multiplying(t.homogeneous[axis], tw, using: &admission), v, using: &admission)
            let d = try r.multiplying(r.multiplying(l.homogeneous[axis], lw, using: &admission), um, using: &admission)
            let f = try r.multiplying(r.multiplying(e.homogeneous[axis], ew, using: &admission), u, using: &admission)
            let lower = try r.adding(r.scaled(c00, by: b.start[axis], using: &admission),
                r.scaled(c10, by: b.end[axis], using: &admission), using: &admission)
            let upper = try r.adding(r.scaled(c01, by: t.start[axis], using: &admission),
                r.scaled(c11, by: t.end[axis], using: &admission), using: &admission)
            let corner = try r.multiplying(r.adding(lower, upper, using: &admission), w, using: &admission)
            laws.append(try r.subtracting(r.adding(r.adding(a, c, using: &admission),
                r.adding(d, f, using: &admission), using: &admission), corner, using: &admission))
        }
        laws.append(w)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
            of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
        let result = OriginalRationalChartReceipt(chart: copy chart, field: copy field, polynomials: r,
            homogeneous: laws, support: support, parameterTransport: .init(numerators: [u, v], denominators: [unit, unit]),
            proofDepth: try admission.depth)
        try admission.checkpoint(); return result
    }
}
