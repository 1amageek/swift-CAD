import CADCore
@testable import CADGeometry
import Testing

@Suite("Regular curve-surface graph authority")
struct CurveSurfaceRegularGraphTests {
    private let intersector: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()

    @Test(.timeLimit(.minutes(1)))
    func broadSourcePositionCannotConsumeFutileRangeLocalizationWork() throws {
        let source = sourceCurve(), target = finiteKnotSurface(tensor: true), options = try graphOptions()
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let range = try ScalarInterval(lower: 0.32, upper: 0.35)
        let axis = try ScalarInterval(lower: 0.3, upper: 0.6)
        let box = SurfaceParameterBox(u: axis, v: axis), pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        var initialOnly = options
        initialOnly.maximumIterations = 1
        var initialBudget = OverlapProofBudget(options: initialOnly, tolerance: .standard)
        let initial = try #require(root.proof(range: range, box: box, pair: pair, budget: &initialBudget))
        #expect(!initial.authority.isSmooth && initial.residual.count == 1)
        let maximumWidth = OutwardScalarInterval.exact(ModelingTolerance.standard.distance) * .exact(2)
        #expect(initial.sourcePositionWidthLowerBound > maximumWidth.upper)
        #expect(initial.residual[0].absoluteUpperBound > ModelingTolerance.standard.distance)
        #expect(initial.residual[0].absoluteLowerBound <= ModelingTolerance.standard.distance)
        var exactInitialWork = options
        // Only the strict certificate fits, despite the original full iteration allowance.
        exactInitialWork.maximumSubdivisionCells = root.jetWork * 4 + target.uKnots.count + target.vKnots.count
        var budget = OverlapProofBudget(options: exactInitialWork, tolerance: .standard)
        let unchanged = try #require(root.proof(range: range, box: box, pair: pair, budget: &budget))
        #expect(unchanged.box == initial.box && unchanged.authority == initial.authority)
        #expect(unchanged.sourcePositionWidthLowerBound == initial.sourcePositionWidthLowerBound)
        #expect(unchanged.residual[0].lower == initial.residual[0].lower
            && unchanged.residual[0].upper == initial.residual[0].upper)
        let lower = finiteKnotInverse(range.lower / (1 + range.lower))
        let upper = finiteKnotInverse(range.upper / (1 + range.upper))
        for axis in [unchanged.box.u, unchanged.box.v] {
            #expect(axis.lower <= lower && axis.upper >= upper)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func tensorCornerRangeLocalizationRetainsEveryOriginalIntervalRoot() throws {
        let source = sourceCurve(), target = finiteKnotSurface(tensor: true), options = try graphOptions()
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let range = try ScalarInterval(lower: 0.5999994277954102, upper: 0.6000000953674316)
        let axis = try ScalarInterval(lower: 0.4999990202481862, upper: 0.5000007934872713)
        let box = SurfaceParameterBox(u: axis, v: axis), pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        var firstOnly = options
        firstOnly.maximumIterations = 1
        var firstBudget = OverlapProofBudget(options: firstOnly, tolerance: .standard)
        let first = try #require(root.proof(range: range, box: box, pair: pair, budget: &firstBudget))
        #expect(first.residual[0].absoluteUpperBound > ModelingTolerance.standard.distance)
        #expect(first.residual[0].absoluteLowerBound <= ModelingTolerance.standard.distance)
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        let refined = try #require(root.proof(range: range, box: box, pair: pair, budget: &budget))
        let lower = finiteKnotInverse(range.lower / (1 + range.lower))
        let upper = finiteKnotInverse(range.upper / (1 + range.upper))
        // h and the literal piecewise-linear inverse are increasing on this full interval.
        for (axis, initial) in [(refined.box.u, first.box.u), (refined.box.v, first.box.v)] {
            #expect(axis.lower <= lower && axis.upper >= upper)
            #expect(axis.lower >= initial.lower && axis.upper <= initial.upper)
            #expect(axis.width < initial.width)
        }
        #expect(refined.authority == first.authority && !refined.authority.isSmooth)
        #expect(refined.u.count == 1 && refined.v.count == 1 && refined.residual.count == 1)
        #expect(refined.u[0].lower == first.u[0].lower && refined.u[0].upper == first.u[0].upper)
        #expect(refined.v[0].lower == first.v[0].lower && refined.v[0].upper == first.v[0].upper)
        #expect(refined.residual[0].absoluteUpperBound <= ModelingTolerance.standard.distance)
        let original = try root.curve.thirdOrderIntervalJet(over: range, tolerance: .standard)
        let image = try root.surface.intervalJet(over: refined.box, tolerance: .standard)
        let residual = original.z.value - image.z.value
        #expect(refined.residual[0].lower == residual.lower && refined.residual[0].upper == residual.upper)
    }

    @Test(.timeLimit(.minutes(1)))
    func tensorCornerRangeLocalizationRequiresStrictRootAndChargesEveryRefinement() throws {
        let source = sourceCurve(), target = finiteKnotSurface(tensor: true), options = try graphOptions()
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let range = try ScalarInterval(lower: 0.5999994277954102, upper: 0.6000000953674316)
        let axis = try ScalarInterval(lower: 0.4999990202481862, upper: 0.5000007934872713)
        let box = SurfaceParameterBox(u: axis, v: axis), pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        let wrongAxis = try ScalarInterval(lower: 0.1, upper: 0.2)
        var unrestricted = OverlapProofBudget(options: options, tolerance: .standard)
        #expect(try root.proof(range: range, box: SurfaceParameterBox(u: wrongAxis, v: wrongAxis),
            pair: pair, budget: &unrestricted) == nil)
        var limited = options
        // The initial strict K proof and its position residual fit exactly.
        limited.maximumSubdivisionCells = root.jetWork * 4 + target.uKnots.count + target.vKnots.count
        var initialOnly = limited
        initialOnly.maximumIterations = 1
        var initialBudget = OverlapProofBudget(options: initialOnly, tolerance: .standard)
        let initial = try #require(root.proof(range: range, box: box, pair: pair, budget: &initialBudget))
        #expect(initial.residual[0].absoluteUpperBound > ModelingTolerance.standard.distance)
        var exhausted = OverlapProofBudget(options: limited, tolerance: .standard)
        try expectFailure(.resourceLimitExceeded) {
            _ = try root.proof(range: range, box: box, pair: pair, budget: &exhausted)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledTensorCornerRangeLocalizationCannotReturnAProof() async throws {
        let source = sourceCurve(), target = finiteKnotSurface(tensor: true), options = try graphOptions()
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let range = try ScalarInterval(lower: 0.5999994277954102, upper: 0.6000000953674316)
        let axis = try ScalarInterval(lower: 0.4999990202481862, upper: 0.5000007934872713)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            var budget = OverlapProofBudget(options: options, tolerance: .standard)
            _ = try root.proof(range: range, box: SurfaceParameterBox(u: axis, v: axis),
                pair: .init(first: 0, second: 1), budget: &budget)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func broadSourceQuotientUsesACompleteDerivativeCoverBeforeTransverseAdmission() throws {
        let source = sourceCurve(), target = finiteKnotSurface(), options = try graphOptions()
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        try budget.preparation(curve: source, surface: target)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let range = try ScalarInterval(lower: 0.275, upper: 0.45000000000000007)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 1),
            v: try ScalarInterval(lower: 0, upper: 0.9427002317387102))
        let original = try root.curve.thirdOrderIntervalJet(over: range, tolerance: .standard)
        #expect(original.x.derivativeU.lower < 0 && original.x.derivativeU.upper > 0)
        #expect(original.y.derivativeU.lower < 0 && original.y.derivativeU.upper > 0)
        let proof = try #require(root.proof(range: range, box: box, pair: .init(first: 0, second: 1), budget: &budget))
        #expect(proof.authority == .collar(u: .init(first: 0.25, last: 0.5, count: 2), v: nil))
        #expect(proof.u.count == 1 && proof.v.count == 1 && proof.residual.count == 1)
        #expect(proof.box.u.lower > box.u.lower && proof.box.u.upper < box.u.upper)
        #expect(proof.box.v.lower > box.v.lower && proof.box.v.upper < box.v.upper)
        // h lies inside the middle native segment, so both true UV derivatives
        // are h'=1/(1+t)^2 throughout the complete original source interval.
        let exactLower = 1 / ((1 + range.upper) * (1 + range.upper))
        let exactUpper = 1 / ((1 + range.lower) * (1 + range.lower))
        #expect(proof.u[0].lower > 0 && proof.u[0].lower <= exactLower && proof.u[0].upper >= exactUpper)
        #expect(proof.v[0].lower > 0 && proof.v[0].lower <= exactLower && proof.v[0].upper >= exactUpper)
        let image = try root.surface.intervalJet(over: proof.box, tolerance: .standard)
        let originalResidual = original.z.value - image.z.value
        #expect(proof.residual[0].lower == originalResidual.lower && proof.residual[0].upper == originalResidual.upper)
    }

    @Test(.timeLimit(.minutes(1)))
    func completeSourceDerivativeCoverHonorsWorkDepthAndIterationLimits() throws {
        let source = sourceCurve(), target = finiteKnotSurface(), options = try graphOptions()
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let range = try ScalarInterval(lower: 0.275, upper: 0.45000000000000007)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 1),
            v: try ScalarInterval(lower: 0, upper: 0.9427002317387102))
        var workLimited = options
        // The strict original chart and cover preflight fit; the next lower jet must be charged.
        workLimited.maximumSubdivisionCells = root.jetWork * 3 + target.uKnots.count + target.vKnots.count + 2
        var work = OverlapProofBudget(options: workLimited, tolerance: .standard)
        try expectFailure(.resourceLimitExceeded) {
            _ = try root.proof(range: range, box: box, pair: .init(first: 0, second: 1), budget: &work)
        }
        var depthLimited = options
        depthLimited.maximumSubdivisionDepth = 0
        var depth = OverlapProofBudget(options: depthLimited, tolerance: .standard)
        try expectFailure(.resourceLimitExceeded) {
            _ = try root.proof(range: range, box: box, pair: .init(first: 0, second: 1), budget: &depth)
        }
        var iterationLimited = options
        iterationLimited.maximumIterations = 1
        var iterations = OverlapProofBudget(options: iterationLimited, tolerance: .standard)
        // Without a complete finer cover the original transverse guard still refuses.
        try expectFailure(.unsupportedCapability) {
            _ = try root.proof(range: range, box: box, pair: .init(first: 0, second: 1), budget: &iterations)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func finiteOriginalKnotAtlasOwnsTwoCrossingsAndTensorCorners() throws {
        for mode in 0..<3 {
            var source = Curve3D.bSpline(sourceCurve())
            var target = Surface3D.bSpline(finiteKnotSurface(swapped: mode == 1, tensor: mode == 2))
            let originalSource = source, originalTarget = target, options = try graphOptions()
            let result = try intersector.intersectionResult(curve: source, surface: target,
                options: options, tolerance: .standard)
            #expect(result.overlaps.count == 1 && result.points.isEmpty)
            let overlap = try #require(result.overlaps.first)
            #expect(overlap.curveRange == options.curveRange)
            #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
            source = .line(Line3D(origin: Point3D(x: 3, y: 4, z: 5), direction: .unitZ))
            target = .plane(Plane3D(origin: .origin, normal: .unitX))
            for t in [0.1, 1.0 / 7.0, 0.3, 3.0 / 5.0, 0.8] {
                let h = t / (1 + t), inverse = finiteKnotInverse(h)
                let value = try overlap.correspondence(at: t)
                #expect(abs(value.surfaceParameter.u - (mode == 1 ? h : inverse)) < 1e-7)
                #expect(abs(value.surfaceParameter.v - (mode == 0 ? h : inverse)) < 1e-7)
                let point = try originalSource.point(at: t, tolerance: .standard)
                #expect((point - Point3D(x: h, y: h, z: h * h)).length < 1e-12)
                let surfacePoint = try originalTarget.point(u: value.surfaceParameter.u,
                    v: value.surfaceParameter.v, tolerance: .standard)
                #expect((point - surfacePoint).length <= ModelingTolerance.standard.distance)
            }
            try expectFailure(.invalidInput) { _ = try overlap.correspondence(at: 0.9) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func finiteOriginalKnotAtlasClipHasIndependentSourceEndpoints() throws {
        for mode in 0..<3 {
            var options = try graphOptions()
            let clip = try ScalarInterval(lower: 0.2, upper: 0.525)
            if mode != 1 { options.surfaceURange = clip }
            if mode != 0 { options.surfaceVRange = clip }
            let result = try intersector.intersectionResult(curve: .bSpline(sourceCurve()),
                surface: .bSpline(finiteKnotSurface(swapped: mode == 1, tensor: mode == 2)),
                options: options, tolerance: .standard)
            #expect(result.overlaps.count == 1 && result.points.isEmpty)
            let overlap = try #require(result.overlaps.first)
            #expect(abs(overlap.curveRange.lower - 1.0 / 9.0) < 1e-8)
            #expect(abs(overlap.curveRange.upper - 17.0 / 23.0) < 1e-8)
            let start = mode == 1 ? overlap.start.surfaceParameter.v : overlap.start.surfaceParameter.u
            let end = mode == 1 ? overlap.end.surfaceParameter.v : overlap.end.surfaceParameter.u
            #expect(abs(start - 0.2) < 2e-9 && abs(end - 0.525) < 2e-9)
            for t in [1.0 / 7.0, 3.0 / 5.0] {
                #expect(try overlap.correspondence(at: t).residual <= ModelingTolerance.standard.distance)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func finiteOriginalTensorKnotZeroWidthRequestsKeepIsolatedCrossings() throws {
        for (knot, expectedSource) in [(0.25, 1.0 / 7.0), (0.5, 3.0 / 5.0)] {
            var options = try graphOptions()
            options.surfaceURange = try ScalarInterval(lower: knot, upper: knot)
            options.surfaceVRange = options.surfaceURange
            let result = try intersector.intersectionResult(curve: .bSpline(sourceCurve()),
                surface: .bSpline(finiteKnotSurface(tensor: true)), options: options, tolerance: .standard)
            #expect(result.overlaps.isEmpty && result.points.count == 1)
            let point = try #require(result.points.first)
            #expect(abs(point.curveParameter - expectedSource) < 1e-8)
            #expect(abs(point.surfaceU - knot) < 2e-9 && abs(point.surfaceV - knot) < 2e-9)
            #expect(point.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func finiteCollarSummariesRetainAllOriginalCornerJacobians() throws {
        let source = sourceCurve(), target = finiteKnotSurface(tensor: true), options = try graphOptions()
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        try budget.preparation(curve: source, surface: target)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let multipleBox = SurfaceParameterBox(u: try ScalarInterval(lower: 0.15, upper: 0.65),
            v: try ScalarInterval(lower: 0.15, upper: 0.65))
        let summary = OverlapRegularGraphAtlas.AxisKnots(first: 0.25, last: 0.5, count: 2)
        #expect(try OverlapRegularGraphAtlas.authority(over: multipleBox, surface: target,
            tolerance: .standard, budget: &budget) == .collar(u: summary, v: summary))
        let station = 0.45
        // This fresh strict root proof spans both native knots on both axes.
        let multiple = try #require(root.proof(range: ScalarInterval(lower: station.nextDown, upper: station.nextUp),
            box: multipleBox, pair: .init(first: 0, second: 1), budget: &budget))
        #expect(multiple.authority == .collar(u: summary, v: summary))
        #expect(multiple.box.u.lower > multipleBox.u.lower && multiple.box.u.upper < multipleBox.u.upper)
        #expect(multiple.box.v.lower > multipleBox.v.lower && multiple.box.v.upper < multipleBox.v.upper)
        #expect(multiple.u.count == 1 && multiple.v.count == 1 && multiple.residual.count == 1)
        for (knot, t, lowerSlope, upperSlope) in [(0.25, 1.0 / 7.0, 0.5, 1.0), (0.5, 3.0 / 5.0, 1.0, 2.0)] {
            let point = try root.surface.pointJet(u: knot, v: knot, tolerance: .standard)
            #expect(point.x.derivativeU.lower <= lowerSlope && point.x.derivativeU.upper >= upperSlope)
            #expect(point.y.derivativeV.lower <= lowerSlope && point.y.derivativeV.upper >= upperSlope)
            #expect(point.x.derivativeV.lower <= 0 && point.x.derivativeV.upper >= 0)
            #expect(point.y.derivativeU.lower <= 0 && point.y.derivativeU.upper >= 0)
            let minor = point.x.derivativeU * point.y.derivativeV - point.x.derivativeV * point.y.derivativeU
            #expect(minor.lower > 0 && minor.lower <= lowerSlope * lowerSlope && minor.upper >= upperSlope * upperSlope)
            let range = try ScalarInterval(lower: t - 1e-8, upper: t + 1e-8)
            let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
            let box = try #require(root.trialBox(range: range, pair: pair,
                seed: SurfaceParameter(u: knot, v: knot), budget: &budget))
            let proof = try #require(root.proof(range: range, box: box, pair: pair, budget: &budget))
            let one = OverlapRegularGraphAtlas.AxisKnots(first: knot, last: knot, count: 1)
            #expect(proof.authority == .collar(u: one, v: one))
            #expect(proof.u.count == 1 && proof.v.count == 1 && proof.residual.count == 1)
            #expect(proof.u[0].lower > 0 && proof.v[0].lower > 0)
            #expect(proof.residual[0].absoluteUpperBound <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func finiteTensorKnotPerturbationCannotAdmitOriginalSpanFragments() throws {
        var source = sourceCurve()
        source.controlPoints[1] = source.controlPoints[1] + Vector3D(x: 0, y: 0, z: 0.125)
        let result = try intersector.intersectionResult(curve: .bSpline(source),
            surface: .bSpline(finiteKnotSurface(tensor: true)), options: graphOptions(), tolerance: .standard)
        // Injective XY fixes both piecewise inverses. The positive Z deviation
        // 0.5*t*(1-t)/(1+t)^2 rules out every exact event on this original span.
        #expect(result.overlaps.isEmpty && result.points.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func finiteTensorKnotRequiresEveryAffectedAxisToBeTransverse() throws {
        for constantU in [true, false] {
            let hControls = [0.0, 0.25, 0.5]
            let source = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                controlPoints: hControls.map {
                    Point3D(x: constantU ? 0.125 : $0, y: constantU ? $0 : 0.125, z: 0.125 * $0)
                }, weights: [1, 2, 4])
            let target = finiteKnotSurface(tensor: true), options = try graphOptions()
            var budget = OverlapProofBudget(options: options, tolerance: .standard)
            try budget.preparation(curve: source, surface: target)
            let root = OverlapRegularGraphRootCertifier(
                curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
                surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
                tolerance: .standard)
            let t = 1.0 / 7.0
            let range = try ScalarInterval(lower: t - 1e-8, upper: t + 1e-8)
            let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
            let box = try #require(root.trialBox(range: range, pair: pair,
                seed: SurfaceParameter(u: 0.25, v: 0.25), budget: &budget))
            try expectFailure(.unsupportedCapability) {
                _ = try root.proof(range: range, box: box, pair: pair, budget: &budget)
            }
            try expectFailure(.unsupportedCapability) {
                _ = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
                    options: options, tolerance: .standard)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func finiteTensorFoldAndCallerLimitsRemainExplicit() async throws {
        let values = [0.0, 0.125, 0.375, 1.375], folded = [0.0, 0.125, 0.375, -0.625]
        let knots = [0.0, 0, 0.25, 0.5, 1, 1]
        let fold = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
            controlPoints: values.map { y in folded.map { x in Point3D(x: x, y: y, z: x * y) } })
        let source = sourceCurve(), options = try graphOptions()
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        try budget.preparation(curve: source, surface: fold)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: fold, tolerance: .standard),
            tolerance: .standard)
        let t = 3.0 / 5.0
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0.5 - 1e-6, upper: 0.5 + 1e-6),
            v: try ScalarInterval(lower: 0.5 - 1e-6, upper: 0.5 + 1e-6))
        #expect(try root.proof(range: ScalarInterval(lower: t.nextDown, upper: t.nextUp),
            box: box, pair: .init(first: 0, second: 1), budget: &budget) == nil)
        let target = finiteKnotSurface(tensor: true)
        for field in 0..<4 {
            var limited = options
            switch field {
            case 0: limited.maximumSubdivisionCells = 2
            case 1: limited.maximumPolynomialDegree = 1
            case 2: limited.maximumSubdivisionDepth = 0
            default: limited.maximumCandidateCount = 1
            }
            try expectFailure(.resourceLimitExceeded) { _ = try certify(source, target, options: limited) }
        }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            _ = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(source),
                surface: .bSpline(target), options: options, tolerance: .standard)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalC1KnotAtlasRetainsWholeOwnedGraphOnEitherAxis() throws {
        for swapped in [false, true] {
            var source = Curve3D.bSpline(sourceCurve())
            var target = Surface3D.bSpline(c1KnotSurface(swapped: swapped))
            let originalSource = source, originalTarget = target, options = try graphOptions()
            let result = try intersector.intersectionResult(curve: source, surface: target,
                options: options, tolerance: .standard)
            #expect(result.overlaps.count == 1 && result.points.isEmpty)
            let overlap = try #require(result.overlaps.first)
            #expect(overlap.curveRange == options.curveRange)
            #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
            source = .line(Line3D(origin: Point3D(x: 7, y: 8, z: 9), direction: .unitX))
            target = .plane(Plane3D(origin: .origin, normal: .unitY))
            for t in [0.1, 0.3, 1.0 / 3.0, 0.4, 0.8] {
                let h = t / (1 + t)
                let varying = h <= 0.25 ? h.squareRoot() : (1 + (8 * h - 1).squareRoot()) / 4
                let value = try overlap.correspondence(at: t)
                #expect(abs(value.surfaceParameter.u - (swapped ? h : varying)) < 1e-7)
                #expect(abs(value.surfaceParameter.v - (swapped ? varying : h)) < 1e-7)
                let sourcePoint = try originalSource.point(at: t, tolerance: .standard)
                #expect((sourcePoint - Point3D(x: h, y: h, z: h * h)).length < 1e-12)
                let targetPoint = try originalTarget.point(u: value.surfaceParameter.u,
                    v: value.surfaceParameter.v, tolerance: .standard)
                #expect((sourcePoint - targetPoint).length <= ModelingTolerance.standard.distance)
            }
            try expectFailure(.invalidInput) { _ = try overlap.correspondence(at: 0.9) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalC1KnotClipHasIndependentSourceEndpoints() throws {
        for swapped in [false, true] {
            var options = try graphOptions()
            let clip = try ScalarInterval(lower: 0.4, upper: 0.55)
            if swapped { options.surfaceVRange = clip } else { options.surfaceURange = clip }
            let result = try intersector.intersectionResult(curve: .bSpline(sourceCurve()),
                surface: .bSpline(c1KnotSurface(swapped: swapped)), options: options, tolerance: .standard)
            #expect(result.overlaps.count == 1 && result.points.isEmpty)
            let overlap = try #require(result.overlaps.first)
            #expect(abs(overlap.curveRange.lower - 4.0 / 21.0) < 1e-8)
            #expect(abs(overlap.curveRange.upper - 61.0 / 139.0) < 1e-8)
            let start = swapped ? overlap.start.surfaceParameter.v : overlap.start.surfaceParameter.u
            let end = swapped ? overlap.end.surfaceParameter.v : overlap.end.surfaceParameter.u
            #expect(abs(start - 0.4) < 2e-9 && abs(end - 0.55) < 2e-9)
            #expect(try overlap.correspondence(at: 1.0 / 3.0).residual <= ModelingTolerance.standard.distance)
            let pointRange = try ScalarInterval(lower: 0.5, upper: 0.5)
            if swapped { options.surfaceVRange = pointRange } else { options.surfaceURange = pointRange }
            let pointResult = try intersector.intersectionResult(curve: .bSpline(sourceCurve()),
                surface: .bSpline(c1KnotSurface(swapped: swapped)), options: options, tolerance: .standard)
            #expect(pointResult.overlaps.isEmpty && pointResult.points.count == 1)
            let point = try #require(pointResult.points.first)
            #expect(abs(point.curveParameter - 1.0 / 3.0) < 1e-8)
            #expect(point.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalC1KnotUsesFirstOrderCollarDespiteSecondDerivativeJump() throws {
        for swapped in [false, true] {
            let source = sourceCurve(), target = c1KnotSurface(swapped: swapped), options = try graphOptions()
            var budget = OverlapProofBudget(options: options, tolerance: .standard)
            try budget.preparation(curve: source, surface: target)
            let root = OverlapRegularGraphRootCertifier(
                curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
                surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
                tolerance: .standard)
            let t = 1.0 / 3.0
            let range = try ScalarInterval(lower: t - 1e-8, upper: t + 1e-8)
            let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
            let seed = SurfaceParameter(u: swapped ? 0.25 : 0.5, v: swapped ? 0.5 : 0.25)
            let point = try root.surface.pointJet(u: seed.u, v: seed.v, tolerance: .standard)
            let second = swapped ? point.x.secondDerivativeVV : point.x.secondDerivativeUU
            // Both owning patches have f'=1, but their f'' values are two and four.
            #expect(second.lower <= 2 && second.upper >= 4)
            let first = swapped ? point.x.derivativeV : point.x.derivativeU
            #expect(first.lower <= 1 && first.upper >= 1)
            let box = try #require(root.trialBox(range: range, pair: pair, seed: seed, budget: &budget))
            let proof = try #require(root.proof(range: range, box: box, pair: pair, budget: &budget))
            let nativeKnot = OverlapRegularGraphAtlas.AxisKnots(first: 0.5, last: 0.5, count: 1)
            #expect(proof.authority == .collar(u: swapped ? nil : nativeKnot, v: swapped ? nativeKnot : nil))
            #expect(proof.u.count == 1 && proof.v.count == 1 && proof.residual.count == 1)
            let derivative = swapped ? proof.v[0] : proof.u[0]
            #expect(derivative.lower > 0 && derivative.lower <= 9.0 / 16.0 && derivative.upper >= 9.0 / 16.0)
            #expect(proof.residual[0].absoluteUpperBound <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func perturbedSourceAcrossOriginalC1KnotReachesActualDiscreteRefusal() throws {
        var source = sourceCurve()
        source.controlPoints[1] = source.controlPoints[1] + Vector3D(x: 0, y: 0, z: 0.125)
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(c1KnotSurface()),
            options: graphOptions(), tolerance: .standard)
        // Injective XY fixes UV; 0.5*t*(1-t)/(1+t)^2 is positive on the whole request.
        #expect(result.overlaps.isEmpty && result.points.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func continuousC1KnotRefusesWhileMultipleAndCornerGraphsRetainAuthority() throws {
        let constant = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0.25, y: 0, z: 0), Point3D(x: 0.25, y: 0.25, z: 0.0625),
                            Point3D(x: 0.25, y: 0.5, z: 0.125)], weights: [1, 2, 4])
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .bSpline(constant), surface: .bSpline(c1KnotSurface()),
                options: graphOptions(), tolerance: .standard)
        }
        let greville = [0.0, 0.125, 0.3125, 0.6875, 1]
        let multiple = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 0.25, 0.375, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [greville.map { Point3D(x: $0, y: 0, z: 0) },
                            greville.map { Point3D(x: $0, y: 1, z: $0) }])
        let options = try graphOptions()
        let multipleResult = try intersector.intersectionResult(curve: .bSpline(sourceCurve()), surface: .bSpline(multiple),
            options: options, tolerance: .standard)
        #expect(multipleResult.points.isEmpty && multipleResult.overlaps.count == 1)
        let multipleOverlap = try #require(multipleResult.overlaps.first)
        #expect(multipleOverlap.curveRange == options.curveRange)
        #expect(multipleOverlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        for t in [0.1, 1.0 / 3.0, 0.6, 0.8] {
            let h = t / (1 + t), value = try multipleOverlap.correspondence(at: t)
            // Greville controls reproduce S=(u,v,u*v) across both original C1 knots.
            #expect(abs(value.surfaceParameter.u - h) < 1e-7 && abs(value.surfaceParameter.v - h) < 1e-7)
            let point = try multiple.point(u: value.surfaceParameter.u, v: value.surfaceParameter.v, tolerance: .standard)
            #expect((point - Point3D(x: h, y: h, z: h * h)).length <= ModelingTolerance.standard.distance)
        }
        let x = [0.0, 0, 0.5, 1.25], knots = [0.0, 0, 0, 0.5, 1, 1, 1]
        let corner = BSplineSurface3D(uDegree: 2, vDegree: 2, uKnots: knots, vKnots: knots,
            controlPoints: x.map { y in x.map { value in Point3D(x: value, y: y, z: value * y) } })
        let cornerResult = try intersector.intersectionResult(curve: .bSpline(sourceCurve()), surface: .bSpline(corner),
            options: options, tolerance: .standard)
        #expect(cornerResult.points.isEmpty && cornerResult.overlaps.count == 1)
        let cornerOverlap = try #require(cornerResult.overlaps.first)
        #expect(cornerOverlap.curveRange == options.curveRange)
        #expect(cornerOverlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        for t in [0.1, 1.0 / 3.0, 0.4, 0.8] {
            let h = t / (1 + t)
            let inverse = h <= 0.25 ? h.squareRoot() : (1 + (8 * h - 1).squareRoot()) / 4
            let value = try cornerOverlap.correspondence(at: t)
            #expect(abs(value.surfaceParameter.u - inverse) < 1e-7 && abs(value.surfaceParameter.v - inverse) < 1e-7)
            let point = try corner.point(u: value.surfaceParameter.u, v: value.surfaceParameter.v, tolerance: .standard)
            #expect((point - Point3D(x: h, y: h, z: h * h)).length <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalC1KnotCallerBudgetsAndCancellationRemainExplicit() async throws {
        let target = c1KnotSurface()
        for field in 0..<4 {
            var options = try graphOptions()
            switch field {
            case 0: options.maximumSubdivisionCells = 2
            case 1: options.maximumPolynomialDegree = 1
            case 2: options.maximumSubdivisionDepth = 0
            default: options.maximumCandidateCount = 1
            }
            try expectFailure(.resourceLimitExceeded) {
                _ = try certify(sourceCurve(), target, options: options)
            }
        }
        let source = sourceCurve(), options = try graphOptions()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            _ = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(source),
                surface: .bSpline(target), options: options, tolerance: .standard)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func pointRootLocalizationContinuesAfterEitherCoordinateReachesItsFloor() throws {
        for swapped in [false, true] {
            let source = sourceCurve(), target = knotSurface(swapped: swapped)
            let options = try graphOptions()
            var budget = OverlapProofBudget(options: options, tolerance: .standard)
            try budget.preparation(curve: source, surface: target)
            let root = OverlapRegularGraphRootCertifier(
                curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
                surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
                tolerance: .standard)
            let t = 0.1904773712158203, h = t / (1 + t)
            let nonlinear = try ScalarInterval(lower: 0.38, upper: 0.42)
            let linear = try ScalarInterval(lower: 0.15, upper: 0.17)
            let box = SurfaceParameterBox(u: swapped ? linear : nonlinear, v: swapped ? nonlinear : linear)
            let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
            let station = try ScalarInterval(lower: t.nextDown, upper: t.nextUp)
            let first = try #require(root.proof(range: station, box: box, pair: pair, budget: &budget))
            let firstNonlinear = swapped ? first.box.v : first.box.u
            let firstLinear = swapped ? first.box.u : first.box.v
            #expect(firstNonlinear.width > 1e-6 && firstLinear.width < 1e-12)
            let cell = OverlapRegularGraphCell(range: try ScalarInterval(lower: 0.1875, upper: 0.1984375),
                box: box, pair: pair, derivativeU: first.u[0], derivativeV: first.v[0], maximumDeviation: .infinity)
            let refined = try root.pointProof(at: t, cell: cell, budget: &budget)
            let refinedNonlinear = swapped ? refined.box.v : refined.box.u
            let refinedLinear = swapped ? refined.box.u : refined.box.v
            // On this original native span S=(u*u,v,u*u*v), so the root is independent.
            #expect(refinedNonlinear.lower <= h.squareRoot() && refinedNonlinear.upper >= h.squareRoot())
            #expect(refinedLinear.lower <= h && refinedLinear.upper >= h)
            #expect(refinedNonlinear.width < 1e-10 && refinedLinear.width < 1e-12)
            #expect(refined.residual[0].absoluteUpperBound <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func pointRootLocalizationRequiresAnInitialStrictCertificateAndCallerWork() throws {
        let source = sourceCurve(), target = knotSurface(), options = try graphOptions()
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let t = 0.1904773712158203
        let range = try ScalarInterval(lower: 0.1875, upper: 0.1984375)
        let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0.38, upper: 0.42),
            v: try ScalarInterval(lower: 0.15, upper: 0.17))
        let cell = OverlapRegularGraphCell(range: range, box: box, pair: pair,
            derivativeU: .exact(1), derivativeV: .exact(1), maximumDeviation: .infinity)
        let unrelated = OverlapRegularGraphCell(range: range,
            box: SurfaceParameterBox(u: try ScalarInterval(lower: 0.7, upper: 0.72),
                v: try ScalarInterval(lower: 0.8, upper: 0.82)), pair: pair,
            derivativeU: .exact(1), derivativeV: .exact(1), maximumDeviation: .infinity)
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        #expect(try root.proof(range: ScalarInterval(lower: t.nextDown, upper: t.nextUp),
            box: unrelated.box, pair: pair, budget: &budget) == nil)
        try expectFailure(.intersectionFailure) {
            _ = try root.pointProof(at: t, cell: unrelated, budget: &budget)
        }
        var limited = options
        // One first certificate fits; its next localization must charge the same budget.
        limited.maximumSubdivisionCells = root.jetWork * 4 + target.uKnots.count + target.vKnots.count
        var oneCertificate = OverlapProofBudget(options: limited, tolerance: .standard)
        _ = try #require(root.proof(range: ScalarInterval(lower: t.nextDown, upper: t.nextUp),
            box: box, pair: pair, budget: &oneCertificate))
        var exhausted = OverlapProofBudget(options: limited, tolerance: .standard)
        try expectFailure(.resourceLimitExceeded) {
            _ = try root.pointProof(at: t, cell: cell, budget: &exhausted)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledPointRootLocalizationCannotReturnACertificate() async throws {
        let source = sourceCurve(), target = knotSurface(), options = try graphOptions()
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let cell = OverlapRegularGraphCell(range: try ScalarInterval(lower: 0.1875, upper: 0.1984375),
            box: SurfaceParameterBox(u: try ScalarInterval(lower: 0.38, upper: 0.42),
                v: try ScalarInterval(lower: 0.15, upper: 0.17)), pair: .init(first: 0, second: 1),
            derivativeU: .exact(1), derivativeV: .exact(1), maximumDeviation: .infinity)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            var budget = OverlapProofBudget(options: options, tolerance: .standard)
            _ = try root.pointProof(at: 0.1904773712158203, cell: cell, budget: &budget)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalC0KnotAtlasRetainsWholeOwnedGraphOnEitherAxis() throws {
        for swapped in [false, true] {
            var source = Curve3D.bSpline(sourceCurve())
            var target = Surface3D.bSpline(knotSurface(swapped: swapped))
            let originalSource = source, originalTarget = target
            let options = try graphOptions()
            let result = try intersector.intersectionResult(curve: source, surface: target,
                options: options, tolerance: .standard)
            #expect(result.overlaps.count == 1 && result.points.isEmpty)
            let overlap = try #require(result.overlaps.first)
            #expect(overlap.curveRange == options.curveRange)
            #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
            source = .line(Line3D(origin: Point3D(x: 4, y: 5, z: 6), direction: .unitZ))
            target = .plane(Plane3D(origin: .origin, normal: .unitX))
            for t in [0.1, 0.3, 1.0 / 3.0, 0.4, 0.8] {
                let h = t / (1 + t)
                let varying = h <= 0.25 ? h.squareRoot() : (0.75 + h).squareRoot() - 0.5
                let value = try overlap.correspondence(at: t)
                #expect(abs(value.surfaceParameter.u - (swapped ? h : varying)) < 1e-7)
                #expect(abs(value.surfaceParameter.v - (swapped ? varying : h)) < 1e-7)
                let sourcePoint = try originalSource.point(at: t, tolerance: .standard)
                #expect((sourcePoint - Point3D(x: h, y: h, z: h * h)).length < 1e-12)
                let targetPoint = try originalTarget.point(u: value.surfaceParameter.u,
                    v: value.surfaceParameter.v, tolerance: .standard)
                #expect((sourcePoint - targetPoint).length <= ModelingTolerance.standard.distance)
            }
            try expectFailure(.invalidInput) { _ = try overlap.correspondence(at: 0.9) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalC0KnotClipHasIndependentSourceEndpoints() throws {
        for swapped in [false, true] {
            var options = try graphOptions()
            let clip = try ScalarInterval(lower: 0.4, upper: 0.55)
            if swapped { options.surfaceVRange = clip } else { options.surfaceURange = clip }
            let result = try intersector.intersectionResult(curve: .bSpline(sourceCurve()),
                surface: .bSpline(knotSurface(swapped: swapped)), options: options, tolerance: .standard)
            #expect(result.overlaps.count == 1 && result.points.isEmpty)
            let overlap = try #require(result.overlaps.first)
            #expect(abs(overlap.curveRange.lower - 4.0 / 21.0) < 1e-8)
            #expect(abs(overlap.curveRange.upper - 141.0 / 259.0) < 1e-8)
            let start = swapped ? overlap.start.surfaceParameter.v : overlap.start.surfaceParameter.u
            let end = swapped ? overlap.end.surfaceParameter.v : overlap.end.surfaceParameter.u
            #expect(abs(start - 0.4) < 2e-9 && abs(end - 0.55) < 2e-9)
            #expect(try overlap.correspondence(at: 1.0 / 3.0).residual <= ModelingTolerance.standard.distance)
            let pointRange = try ScalarInterval(lower: 0.5, upper: 0.5)
            if swapped { options.surfaceVRange = pointRange } else { options.surfaceURange = pointRange }
            let pointResult = try intersector.intersectionResult(curve: .bSpline(sourceCurve()),
                surface: .bSpline(knotSurface(swapped: swapped)), options: options, tolerance: .standard)
            #expect(pointResult.overlaps.isEmpty && pointResult.points.count == 1)
            let point = try #require(pointResult.points.first)
            #expect(abs(point.curveParameter - 1.0 / 3.0) < 1e-8)
            #expect(point.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func knotCollarExposesOnlyOneSidedFirstDerivativeAuthority() throws {
        let source = sourceCurve(), target = knotSurface()
        let options = try graphOptions()
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        try budget.preparation(curve: source, surface: target)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let t = 1.0 / 3.0
        let range = try ScalarInterval(lower: t - 1e-8, upper: t + 1e-8)
        let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        let box = try #require(root.trialBox(range: range, pair: pair,
            seed: SurfaceParameter(u: 0.5, v: 0.25), budget: &budget))
        let proof = try #require(root.proof(range: range, box: box, pair: pair, budget: &budget))
        #expect(proof.authority == .collar(u: .init(first: 0.5, last: 0.5, count: 1), v: nil))
        #expect(proof.u.count == 1 && proof.v.count == 1 && proof.residual.count == 1)
        // At the crossing, h'=9/16; f' is one on the left and two on the right.
        #expect(proof.u[0].lower <= 9.0 / 32.0 && proof.u[0].upper >= 9.0 / 16.0)
        #expect(proof.u[0].lower > 0 && proof.v[0].lower > 0)
        #expect(proof.residual[0].absoluteUpperBound <= ModelingTolerance.standard.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func perturbedSourceAcrossOriginalKnotReachesActualDiscreteRefusal() throws {
        var source = sourceCurve()
        source.controlPoints[1] = source.controlPoints[1] + Vector3D(x: 0, y: 0, z: 0.125)
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(knotSurface()),
            options: graphOptions(), tolerance: .standard)
        // Injective XY fixes the piecewise UV graph; the positive deviation
        // 0.5*t*(1-t)/(1+t)^2 prevents every exact event on the requested span.
        #expect(result.overlaps.isEmpty && result.points.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func continuousNativeKnotRefusesWhileTensorCornerRetainsOwnedGraph() throws {
        let constantKnot = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0.25, y: 0, z: 0), Point3D(x: 0.25, y: 0.25, z: 0.0625),
                            Point3D(x: 0.25, y: 0.5, z: 0.125)], weights: [1, 2, 4])
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .bSpline(constantKnot), surface: .bSpline(knotSurface()),
                options: graphOptions(), tolerance: .standard)
        }
        let x = [0.0, 0, 0.25, 0.75, 1.5]
        let knots = [0.0, 0, 0, 0.5, 0.5, 1, 1, 1]
        let corner = BSplineSurface3D(uDegree: 2, vDegree: 2, uKnots: knots, vKnots: knots,
            controlPoints: x.map { y in x.map { value in Point3D(x: value, y: y, z: value * y) } })
        let options = try graphOptions()
        let result = try intersector.intersectionResult(curve: .bSpline(sourceCurve()), surface: .bSpline(corner),
            options: options, tolerance: .standard)
        #expect(result.points.isEmpty && result.overlaps.count == 1)
        let overlap = try #require(result.overlaps.first)
        #expect(overlap.curveRange == options.curveRange)
        #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        for t in [0.1, 1.0 / 3.0, 0.4, 0.8] {
            let h = t / (1 + t)
            let inverse = h <= 0.25 ? h.squareRoot() : (0.75 + h).squareRoot() - 0.5
            let value = try overlap.correspondence(at: t)
            #expect(abs(value.surfaceParameter.u - inverse) < 1e-7 && abs(value.surfaceParameter.v - inverse) < 1e-7)
            let point = try corner.point(u: value.surfaceParameter.u, v: value.surfaceParameter.v, tolerance: .standard)
            #expect((point - Point3D(x: h, y: h, z: h * h)).length <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func opposingNativeMinorsAndAtlasBudgetsCannotAdmit() throws {
        let target = knotSurface()
        var fold = target
        fold.controlPoints[0][3].x = 0
        fold.controlPoints[0][4].x = -0.25
        fold.controlPoints[1][3] = Point3D(x: 0, y: 1, z: 0)
        fold.controlPoints[1][4] = Point3D(x: -0.25, y: 1, z: -0.25)
        let source = sourceCurve(), options = try graphOptions()
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        try budget.preparation(curve: source, surface: fold)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: fold, tolerance: .standard),
            tolerance: .standard)
        let t = 1.0 / 3.0
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0.5 - 1e-6, upper: 0.5 + 1e-6),
            v: try ScalarInterval(lower: 0.25 - 1e-6, upper: 0.25 + 1e-6))
        #expect(try root.proof(range: ScalarInterval(lower: t.nextDown, upper: t.nextUp),
            box: box, pair: .init(first: 0, second: 1), budget: &budget) == nil)
        for field in 0..<4 {
            var limited = options
            switch field {
            case 0: limited.maximumSubdivisionCells = 2
            case 1: limited.maximumPolynomialDegree = 1
            case 2: limited.maximumSubdivisionDepth = 0
            default: limited.maximumCandidateCount = 1
            }
            try expectFailure(.resourceLimitExceeded) { _ = try certify(source, target, options: limited) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func constantCoordinatePointResidualUsesCertifiedRootImage() throws {
        // Independently, C(t)=(h,0.5,0.5*h) and S(u,0.5)=(h,0.5,0.5*h)
        // for h=t/(1+t), u=(h+sqrt(h*h+4*h))/2.
        let source = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0.5, z: 0), Point3D(x: 0.25, y: 0.5, z: 0.125),
                            Point3D(x: 0.5, y: 0.5, z: 0.25)], weights: [1, 2, 4])
        let target = targetSurface(), options = try graphOptions()
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        try budget.preparation(curve: source, surface: target)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let t = 0.63, h = t / (1 + t)
        let u = (h + (h * h + 4 * h).squareRoot()) / 2
        let range = try ScalarInterval(lower: t - 1e-4, upper: t + 1e-4)
        let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        let box = try #require(root.trialBox(range: range, pair: pair,
            seed: SurfaceParameter(u: u, v: 0.5), budget: &budget))
        let whole = try #require(root.proof(range: range, box: box, pair: pair, budget: &budget))
        let cell = OverlapRegularGraphCell(range: range, box: box, pair: pair,
            derivativeU: whole.u[0], derivativeV: whole.v[0], maximumDeviation: .infinity)
        let point = try root.pointProof(at: t, cell: cell, budget: &budget)
        #expect(point.residual[0].lower <= 0 && point.residual[0].upper >= 0)
        #expect(point.residual[0].absoluteUpperBound <= ModelingTolerance.standard.distance)
        for derivative in point.residual.dropFirst() {
            #expect(derivative.lower <= 0 && derivative.upper >= 0)
        }
        #expect(point.box.v.lower <= 0.5 && point.box.v.upper >= 0.5)
    }

    @Test(.timeLimit(.minutes(1)))
    func trialTubeContainsIndependentHomogeneousValueUncertainty() throws {
        let source = sourceCurve(), target = targetSurface()
        let options = try graphOptions()
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        try budget.preparation(curve: source, surface: target)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let range = try ScalarInterval(lower: 0.45 - 1e-6, upper: 0.45 + 1e-6)
        let h = range.midpoint / (1 + range.midpoint)
        let u = (h + (h * h + 4 * h).squareRoot()) / 2
        let seed = SurfaceParameter(u: u, v: h)
        let sourceJet = try root.curve.thirdOrderIntervalJet(over: range, tolerance: .standard)
        let targetPoint = try root.surface.pointJet(u: u, v: h, tolerance: .standard)
        let minor = targetPoint.x.derivativeU * targetPoint.y.derivativeV
            - targetPoint.x.derivativeV * targetPoint.y.derivativeU
        let uMotion = try #require((targetPoint.y.derivativeV * sourceJet.x.derivativeU
            - targetPoint.x.derivativeV * sourceJet.y.derivativeU).divided(by: minor)).absoluteUpperBound
        let vMotion = try #require((targetPoint.x.derivativeU * sourceJet.y.derivativeU
            - targetPoint.y.derivativeU * sourceJet.x.derivativeU).divided(by: minor)).absoluteUpperBound
        let derivativeBox = SurfaceParameterBox(u: try ScalarInterval(lower: u - uMotion * range.width, upper: u + uMotion * range.width),
            v: try ScalarInterval(lower: h - vMotion * range.width, upper: h + vMotion * range.width))
        let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        #expect(try root.proof(range: range, box: derivativeBox, pair: pair, budget: &budget) == nil)
        let box = try #require(root.trialBox(range: range, pair: pair, seed: seed, budget: &budget))
        #expect(box.u.lower <= derivativeBox.u.lower && box.u.upper >= derivativeBox.u.upper)
        #expect(box.v.lower <= derivativeBox.v.lower && box.v.upper >= derivativeBox.v.upper)
        let proof = try #require(root.proof(range: range, box: box, pair: pair, budget: &budget))
        #expect(proof.box.u.lower > box.u.lower && proof.box.u.upper < box.u.upper)
        #expect(proof.box.v.lower > box.v.lower && proof.box.v.upper < box.v.upper)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactPreparedCenterSupportsStrictSeedContraction() throws {
        let source = sourceCurve(), target = targetSurface()
        let options = try graphOptions()
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        try budget.preparation(curve: source, surface: target)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let t = 0.45, h = t / (1 + t)
        let u = (h + (h * h + 4 * h).squareRoot()) / 2
        let radius = Double.ulpOfOne * 128
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: u - radius, upper: u + radius),
            v: try ScalarInterval(lower: h - radius, upper: h + radius))
        let whole = try root.surface.intervalJet(over: box, tolerance: .standard)
        let point = try root.surface.pointJet(u: box.u.midpoint, v: box.v.midpoint, tolerance: .standard)
        #expect(point.y.value.lower <= h && point.y.value.upper >= h)
        #expect(point.y.value.upper - point.y.value.lower < whole.y.value.upper - whole.y.value.lower)
        let minor = whole.x.derivativeU * whole.y.derivativeV - whole.x.derivativeV * whole.y.derivativeU
        #expect(minor.lower > 0)
        let proof = try #require(root.proof(range: ScalarInterval(lower: t.nextDown, upper: t.nextUp),
            box: box, pair: .init(first: 0, second: 1), budget: &budget))
        #expect(proof.box.u.lower > box.u.lower && proof.box.u.upper < box.u.upper)
        #expect(proof.box.v.lower > box.v.lower && proof.box.v.upper < box.v.upper)
    }

    @Test(.timeLimit(.minutes(1)))
    func algebraicUVGraphOwnsWholeRequestedInterval() throws {
        var source = Curve3D.bSpline(sourceCurve())
        var target = Surface3D.bSpline(targetSurface())
        let originalSource = source, originalTarget = target
        let options = try graphOptions()
        let result = try intersector.intersectionResult(curve: source, surface: target,
            options: options, tolerance: .standard)
        #expect(result.points.isEmpty && result.overlaps.count == 1)
        let overlap = try #require(result.overlaps.first)
        #expect(overlap.curveRange == options.curveRange)
        #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        source = .line(Line3D(origin: Point3D(x: 8, y: 9, z: 10), direction: .unitY))
        target = .plane(Plane3D(origin: .origin, normal: .unitX))
        for t in [0.1, 0.2, 0.43, 0.8] {
            let value = try overlap.correspondence(at: t)
            let h = t / (1 + t)
            let expectedU = (h + (h * h + 4 * h).squareRoot()) / 2
            #expect(abs(value.surfaceParameter.u - expectedU) < 1e-7)
            #expect(abs(value.surfaceParameter.v - h) < 1e-7)
            let expected = Point3D(x: h, y: h, z: h * h)
            #expect((value.point - expected).length < 1e-12)
            let sourcePoint = try originalSource.point(at: t, tolerance: .standard)
            let targetPoint = try originalTarget.point(u: value.surfaceParameter.u,
                v: value.surfaceParameter.v, tolerance: .standard)
            #expect((sourcePoint - targetPoint).length <= ModelingTolerance.standard.distance)
        }
        try expectFailure(.invalidInput) { _ = try overlap.correspondence(at: 0.9) }
    }

    @Test(.timeLimit(.minutes(1)))
    func transverseUClipHasIndependentAlgebraicEndpoints() throws {
        var options = try graphOptions()
        options.surfaceURange = try ScalarInterval(lower: 0.5, upper: 0.75)
        let result = try intersector.intersectionResult(curve: .bSpline(sourceCurve()),
            surface: .bSpline(targetSurface()), options: options, tolerance: .standard)
        #expect(result.points.isEmpty && result.overlaps.count == 1)
        let overlap = try #require(result.overlaps.first)
        #expect(abs(overlap.curveRange.lower - 0.2) < 1e-8)
        #expect(abs(overlap.curveRange.upper - 9.0 / 19.0) < 1e-8)
        #expect(abs(overlap.start.surfaceParameter.u - 0.5) < 2e-9)
        #expect(abs(overlap.end.surfaceParameter.u - 0.75) < 2e-9)
        #expect(overlap.start.residual <= ModelingTolerance.standard.distance)
        #expect(overlap.end.residual <= ModelingTolerance.standard.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func middleZPerturbationCannotReceiveContinuousMembership() throws {
        var source = sourceCurve()
        source.controlPoints[1] = source.controlPoints[1] + Vector3D(x: 0, y: 0, z: 0.125)
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(targetSurface()),
            options: graphOptions(), tolerance: .standard)
        // Injective target XY fixes u and v. The remaining deviation is
        // 0.5*t*(1-t)/(1+t)^2 > 0 throughout this requested interval.
        #expect(result.overlaps.isEmpty && result.points.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func distinctCertifiedUVBranchesAreAmbiguous() throws {
        let target = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 1, y: 0, z: 0), Point3D(x: -1, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 1, y: 1, z: 1), Point3D(x: -1, y: 1, z: -1), Point3D(x: 1, y: 1, z: 1)]])
        // S((1 +/- sqrt(h))/2,h) = (h,h,h*h): two distinct roots.
        try expectFailure(.ambiguousSelection) { _ = try certify(sourceCurve(), target) }
    }

    @Test(.timeLimit(.minutes(1)))
    func singularTargetCannotSupplyARegularMinor() throws {
        let row = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0)]
        let target = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [row, row], weights: [[1, 1.5, 2], [1, 1.5, 2]])
        try expectFailure(.singularSystem) { _ = try certify(sourceCurve(), target) }
    }

    @Test(.timeLimit(.minutes(1)))
    func continuousChartBoundaryRequiresExplicitRefusal() throws {
        let source = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0.5, z: 0), Point3D(x: 0.25, y: 0.5, z: 0.125),
                            Point3D(x: 0.5, y: 0.5, z: 0.25)], weights: [1, 2, 4])
        var options = try graphOptions()
        options.surfaceVRange = try ScalarInterval(lower: 0.5, upper: 0.75)
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(targetSurface()),
                options: options, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cumulativePreparationDegreeDepthAndStorageBudgetsRefuse() throws {
        for field in 0..<4 {
            var options = try graphOptions()
            switch field {
            case 0: options.maximumSubdivisionCells = 2
            case 1: options.maximumPolynomialDegree = 1
            case 2: options.maximumSubdivisionDepth = 0
            default: options.maximumCandidateCount = 1
            }
            try expectFailure(.resourceLimitExceeded) {
                _ = try certify(sourceCurve(), targetSurface(), options: options)
            }
        }
    }

    private func sourceCurve() -> BSplineCurve3D {
        BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.25, y: 0.25, z: 0),
                            Point3D(x: 0.5, y: 0.5, z: 0.25)], weights: [1, 2, 4])
    }

    private func targetSurface() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 0, y: 1, z: 0), Point3D(x: 0.5, y: 1, z: 0.5)]],
            weights: [[1, 1.5, 2], [1, 1.5, 2]])
    }

    private func knotSurface(swapped: Bool = false) -> BSplineSurface3D {
        let x = [0.0, 0, 0.25, 0.75, 1.5]
        let rows = [x.map { Point3D(x: $0, y: 0, z: 0) }, x.map { Point3D(x: $0, y: 1, z: $0) }]
        let uKnots = [0.0, 0, 0, 0.5, 0.5, 1, 1, 1], vKnots = [0.0, 0, 1, 1]
        if swapped {
            return BSplineSurface3D(uDegree: 1, vDegree: 2, uKnots: vKnots, vKnots: uKnots,
                controlPoints: x.indices.map { [rows[0][$0], rows[1][$0]] })
        }
        return BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: uKnots, vKnots: vKnots,
            controlPoints: rows)
    }

    private func c1KnotSurface(swapped: Bool = false) -> BSplineSurface3D {
        let x = [0.0, 0, 0.5, 1.25]
        let rows = [x.map { Point3D(x: $0, y: 0, z: 0) }, x.map { Point3D(x: $0, y: 1, z: $0) }]
        let uKnots = [0.0, 0, 0, 0.5, 1, 1, 1], vKnots = [0.0, 0, 1, 1]
        if swapped {
            return BSplineSurface3D(uDegree: 1, vDegree: 2, uKnots: vKnots, vKnots: uKnots,
                controlPoints: x.indices.map { [rows[0][$0], rows[1][$0]] })
        }
        return BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: uKnots, vKnots: vKnots,
            controlPoints: rows)
    }

    private func finiteKnotSurface(swapped: Bool = false, tensor: Bool = false) -> BSplineSurface3D {
        let x = [0.0, 0.125, 0.375, 1.375], knots = [0.0, 0, 0.25, 0.5, 1, 1]
        if tensor {
            return BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
                controlPoints: x.map { y in x.map { value in Point3D(x: value, y: y, z: value * y) } })
        }
        let rows = [x.map { Point3D(x: $0, y: 0, z: 0) }, x.map { Point3D(x: $0, y: 1, z: $0) }]
        let linearKnots = [0.0, 0, 1, 1]
        if swapped {
            return BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: linearKnots, vKnots: knots,
                controlPoints: x.indices.map { [rows[0][$0], rows[1][$0]] })
        }
        return BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: linearKnots,
            controlPoints: rows)
    }

    private func finiteKnotInverse(_ h: Double) -> Double {
        if h <= 0.125 { return 2 * h }
        if h <= 0.375 { return h + 0.125 }
        return (h + 0.625) / 2
    }

    private func graphOptions() throws -> CurveSurfaceIntersectionOptions {
        .init(curveRange: try ScalarInterval(lower: 0.1, upper: 0.8), maximumSubdivisionDepth: 20,
              maximumSubdivisionCells: 4_194_304, maximumCandidateCount: 16_384)
    }

    private func certify(_ curve: BSplineCurve3D, _ surface: BSplineSurface3D,
                         options supplied: CurveSurfaceIntersectionOptions? = nil) throws -> OverlapRegularGraphCertifier.Result {
        let options: CurveSurfaceIntersectionOptions
        if let supplied { options = supplied } else { options = try graphOptions() }
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        return try OverlapRegularGraphCertifier().resolve(curve: curve, surface: surface,
            range: #require(options.curveRange), options: options, tolerance: .standard, budget: &budget)
    }

    private func expectFailure(_ code: KernelErrorCode, _ operation: () throws -> Void) throws {
        do { try operation(); Issue.record("The proof must explicitly refuse this input.") }
        catch let error as KernelError { #expect(error.code == code) }
    }
}
