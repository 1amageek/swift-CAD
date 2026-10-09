import L0
import L1
import SourceIssuer

extension SourceFixtures {
    public static func finiteFamilyCharts() throws {
        try finiteNativeFamilies()
        var a = try TraceAdmission()
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 2)
        let ruled = try ruledReceipt(using: &a), f = ruled.field
        let ruledPreparer = DefaultOriginalFiniteRuledChartPreparer<RuledInput,
            OriginalBSplineChartSelection, OriginalLinearChartSelection, Field>()
        var measured = try TraceAdmission()
        let rs = try ruledPreparer.prepare(source: ruled.source, first: [ruled.chart.selection.first],
            second: [ruled.chart.selection.second], field: f, maximumCharts: 4, limits: limits, using: &measured)
        try require(rs.count == 1)
        for axis in 0..<4 { try require(try ruled.polynomials.equals(ruled.polynomials.importing(rs[0].homogeneous[axis], using: &a), ruled.homogeneous[axis], using: &a)) }
        do { _ = try ruledPreparer.prepare(source: ruled.source, first: [ruled.chart.selection.first],
            second: [ruled.chart.selection.second], field: f, maximumCharts: 0, limits: limits, using: &a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        let foreignLine = try coonsLine([0,1,1], [2,0,0], using: &a)
        do { _ = try ruledPreparer.prepare(source: ruled.source, first: [], second: [foreignLine],
            field: f, maximumCharts: 4, limits: limits, using: &a); throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        var exact = try TraceAdmission(work: measured.work, storage: measured.storageBytes)
        _ = try ruledPreparer.prepare(source: ruled.source, first: [ruled.chart.selection.first],
            second: [ruled.chart.selection.second], field: f, maximumCharts: 4, limits: limits, using: &exact)
        var low = try TraceAdmission(work: measured.work - 1, storage: measured.storageBytes)
        do { _ = try ruledPreparer.prepare(source: ruled.source, first: [ruled.chart.selection.first],
            second: [ruled.chart.selection.second], field: f, maximumCharts: 4, limits: limits, using: &low)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        var storage = try TraceAdmission(work: measured.work, storage: measured.storageBytes - 1)
        do { _ = try ruledPreparer.prepare(source: ruled.source, first: [ruled.chart.selection.first],
            second: [ruled.chart.selection.second], field: f, maximumCharts: 4, limits: limits, using: &storage)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        var cancel = try TraceAdmission(cancelAtStorage: measured.storageCalls)
        do { _ = try ruledPreparer.prepare(source: ruled.source, first: [ruled.chart.selection.first],
            second: [ruled.chart.selection.second], field: f, maximumCharts: 4, limits: limits, using: &cancel)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        let coons = try coonsReceipt(using: &a), c = coons.chart.selection
        let cs = try DefaultOriginalFiniteCoonsChartPreparer<CoonsInput, OriginalBSplineChartSelection,
            OriginalParameterImageChartSelection<LineInput, OriginalLinearChartSelection, Field>,
            OriginalLinearChartSelection, OriginalLinearChartSelection, Field>().prepare(source: coons.source,
                bottom: [c.bottom], top: [c.top], left: [c.left], right: [c.right], field: coons.field,
                maximumCharts: 4, limits: limits, using: &a)
        try require(cs.count == 1)
        for axis in 0..<4 { try require(try coons.polynomials.equals(coons.polynomials.importing(cs[0].homogeneous[axis], using: &a), coons.homogeneous[axis], using: &a)) }
        let spatial = try spatialReceipt(using: &a)
        let ss = try DefaultOriginalFiniteSpatialChartPreparer<SpatialInput<Field.Value>, OriginalBSplineChartSelection, Field>()
            .prepare(source: spatial.source, children: [spatial.chart.selection.child], field: spatial.field,
                coefficients: DefaultOriginalSourceCoefficientImporter<Field>(), maximumCharts: 4, limits: limits, using: &a)
        for axis in 0..<4 { try require(try spatial.polynomials.equals(spatial.polynomials.importing(ss[0].homogeneous[axis], using: &a), spatial.homogeneous[axis], using: &a)) }
        let traversal = try traversalReceipt(using: &a)
        let ts = try DefaultOriginalFiniteTraversalChartPreparer<TraversalInput, OriginalBSplineChartSelection, Field>()
            .prepare(source: traversal.source, children: [traversal.chart.selection.child], field: traversal.field,
                coefficients: DefaultOriginalSourceCoefficientImporter<Field>(), maximumCharts: 4, limits: limits, using: &a)
        try require(ts.count == 1)
        let endpoints = try DefaultOriginalFiniteCoonsBoundaryPreparer<TraversalInput,
            OriginalTraversalChartSelection<NativeSnapshot, OriginalBSplineChartSelection, Field>, Field>()
            .prepare(source: traversal.source, curves: ts, field: traversal.field, limits: limits, using: &a)
        try require(try f.compare(endpoints[0].start.localParameter, f.integer(4, using: &a), using: &a) == .equal)
        try require(try f.compare(endpoints[0].end.localParameter, f.integer(3, using: &a), using: &a) == .equal)
        let ps = try DefaultOriginalFiniteParameterImageChartPreparer<ParameterInput<LineInput>, OriginalLinearChartSelection, Field>()
            .prepare(source: c.top.curve.source, children: [c.top.curve.chart.selection.child], field: f,
                maximumCharts: 4, limits: limits, using: &a)
        for axis in 0..<4 { try require(try c.top.curve.polynomials.equals(c.top.curve.polynomials.importing(ps[0].homogeneous[axis], using: &a), c.top.curve.homogeneous[axis], using: &a)) }
        print("PASS finite ruled/Coons/spatial/parameter/traversal chart composition, reversed exact corners, full laws and atomic limits")
    }
}
