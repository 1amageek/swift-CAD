import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct FiniteCoonsInput: OriginalCoonsSourceReading {
        let bottomBoundary: OriginalSourceBinding<NativeSnapshot>
        let topBoundary: OriginalSourceBinding<NativeSnapshot>
        let leftBoundary: OriginalSourceBinding<NativeSnapshot>
        let rightBoundary: OriginalSourceBinding<NativeSnapshot>
    }
    struct FiniteCoonsProvider: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing FiniteCoonsInput,
            limits: OriginalSourceIssuanceLimits, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<FiniteCoonsInput> {
            do { try admission.checkpoint(); try admission.consumeWork(1) }
            catch { throw .scalar(error) }
            return .init(original: copy input, sourceDepth: 1)
        }
    }
    static func finiteNativeFamilies() throws {
        var a = try TraceAdmission()
        let f = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 2)
        let provider = DefaultOriginalSourceBindingIssuer(provider: NativeProvider())
        let prepare = DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>()
        let weighted = NativeInput(degrees: [1], knots: [[0,0,1,2,2]], counts: [3],
            controls: [[0,0,0],[1,0,0],[2,0,0]], weights: [1,2,1], periodic: [false])
        let source = try provider.bind(weighted, limits: limits, using: &a)
        var measured = try TraceAdmission()
        let full = try prepare.prepare(source: source, field: f, maximumCharts: 2, limits: limits, using: &measured)
        try require(full.laws.count == 2 && full.support.count == 1)
        try require(try f.compare(full.support[0].lower, f.integer(0, using: &a), using: &a) == .equal)
        try require(try f.compare(full.support[0].upper, f.integer(2, using: &a), using: &a) == .equal)
        for index in 0..<2 {
            let law = full.laws[index], r = law.polynomials
            try require(source.owns(law.chart) && law.chart.selection.spans == [index + 1])
            let expected = index == 0 ? try r.scaled(r.variable(0, using: &a), by: f.integer(2, using: &a), using: &a)
                : try r.constant(f.integer(2, using: &a), using: &a)
            try require(try r.equals(law.homogeneous[0], expected, using: &a))
        }
        try require(try f.compare(full.laws[0].support[0].upper, full.laws[1].support[0].lower, using: &a) == .equal)
        var exact = try TraceAdmission(work: measured.work, storage: measured.storageBytes)
        _ = try prepare.prepare(source: source, field: f, maximumCharts: 2, limits: limits, using: &exact)
        var lowWork = try TraceAdmission(work: measured.work - 1, storage: measured.storageBytes)
        do { _ = try prepare.prepare(source: source, field: f, maximumCharts: 2, limits: limits, using: &lowWork)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var lowStorage = try TraceAdmission(work: measured.work, storage: measured.storageBytes - 1)
        do { _ = try prepare.prepare(source: source, field: f, maximumCharts: 2, limits: limits, using: &lowStorage)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        do { _ = try prepare.prepare(source: source, field: f, maximumCharts: 1, limits: limits, using: &a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        let tensor = NativeInput(degrees: [1,1], knots: [[0,0,0.5,1,1],[0,0,0.5,1,1]], counts: [3,3],
            controls: [[0,0,0],[0,0.5,0],[0,1,0],[0.5,0,0],[0.5,0.5,0],[0.5,1,0],[1,0,0],[1,0.5,0],[1,1,0]],
            weights: [1,2,1,2,1,2,1,2,1], periodic: [false,false])
        let tensorSource = try provider.bind(tensor, limits: limits, using: &a)
        let tensorCharts = try prepare.prepare(source: tensorSource, field: f, maximumCharts: 4, limits: limits, using: &a)
        try require(tensorCharts.laws.count == 4 && tensorCharts.support.count == 2)
        for law in tensorCharts.laws {
            let selection = law.chart.selection.spans
            try require(tensorSource.owns(law.chart) && selection.count == 2)
            for du in 0..<2 { for dv in 0..<2 {
                let i = selection[0] - 1 + du, j = selection[1] - 1 + dv, control = j * 3 + i
                let uv = [try f.binary64(exactly: Double(i) * 0.5, using: &a),
                    try f.binary64(exactly: Double(j) * 0.5, using: &a)]
                for axis in 0..<4 {
                    let value = try law.polynomials.evaluated(law.homogeneous[axis], at: uv, using: &a).value
                    let expected = tensor.weights[control] * (axis == 3 ? 1 : tensor.controls[control][axis])
                    try require(try f.compare(value, f.binary64(exactly: expected, using: &a), using: &a) == .equal)
                }
            } }
        }
        do { _ = try prepare.prepare(source: tensorSource, field: f, maximumCharts: 3, limits: limits, using: &a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        let coordinates = [
            [[0.0,0,0],[0.5,0,0],[1,0,0]],
            [[0.0,1,0],[0.5,1,0],[1,1,0]],
            [[0.0,0,0],[0,0.5,0],[0,1,0]],
            [[1.0,0,0],[1,0.5,0],[1,1,0]]
        ]
        var boundaries: [OriginalFiniteBSplineCharts<NativeSnapshot>] = []
        for controls in coordinates {
            let input = NativeInput(degrees: [1], knots: [[0,0,0.5,1,1]], counts: [3],
                controls: controls, weights: [1,1,1], periodic: [false])
            let binding = try provider.bind(input, limits: limits, using: &a)
            boundaries.append(try prepare.prepare(source: binding, field: f, maximumCharts: 2, limits: limits, using: &a))
        }
        let parent = try DefaultOriginalSourceBindingIssuer(provider: FiniteCoonsProvider()).bind(
            FiniteCoonsInput(bottomBoundary: boundaries[0].source, topBoundary: boundaries[1].source,
                leftBoundary: boundaries[2].source, rightBoundary: boundaries[3].source), limits: limits, using: &a)
        let corners = DefaultOriginalFiniteCoonsBoundaryPreparer<NativeSnapshot, OriginalBSplineChartSelection, OriginalExactScalarDomain>()
        let bottom = try corners.prepare(source: boundaries[0].source, curves: boundaries[0].laws, field: f, limits: limits, using: &a)
        let top = try corners.prepare(source: boundaries[1].source, curves: boundaries[1].laws, field: f, limits: limits, using: &a)
        let left = try corners.prepare(source: boundaries[2].source, curves: boundaries[2].laws, field: f, limits: limits, using: &a)
        let right = try corners.prepare(source: boundaries[3].source, curves: boundaries[3].laws, field: f, limits: limits, using: &a)
        let coons = DefaultOriginalFiniteCoonsChartPreparer<FiniteCoonsInput, OriginalBSplineChartSelection,
            OriginalBSplineChartSelection, OriginalBSplineChartSelection, OriginalBSplineChartSelection, OriginalExactScalarDomain>()
        let laws = try coons.prepare(source: parent, bottom: bottom, top: top, left: left, right: right,
            field: f, maximumCharts: 16, limits: limits, using: &a)
        try require(laws.count == 16)
        for law in laws {
            let r = law.polynomials
            try require(try r.equals(law.homogeneous[0], r.variable(0, using: &a), using: &a))
            try require(try r.equals(law.homogeneous[1], r.variable(1, using: &a), using: &a))
            try require(try r.isZero(law.homogeneous[2], using: &a))
            try require(try r.equals(law.denominator, r.constant(f.integer(1, using: &a), using: &a), using: &a))
        }
        do { _ = try coons.prepare(source: parent, bottom: bottom, top: top, left: left, right: right,
            field: f, maximumCharts: 15, limits: limits, using: &a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        print("PASS complete weighted two-span Native preparation and all 16 Coons chart owners, cross-span corner witnesses and exact limits")
    }
}
