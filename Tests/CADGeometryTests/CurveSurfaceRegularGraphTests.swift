import CADCore
@testable import CADGeometry
import Testing

@Suite("Regular curve-surface graph authority")
struct CurveSurfaceRegularGraphTests {
    private let intersector: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()

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
