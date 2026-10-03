import CADCore
@testable import CADGeometry
import Testing

@Suite("Regular curve-surface graph authority")
struct CurveSurfaceRegularGraphTests {
    private let intersector: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()

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
            #expect(proof.authority == .collar(axis: swapped ? .v : .u, knot: 0.5))
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
    func continuousC1KnotMultipleLowKnotsAndC1CornerRemainUnsupported() throws {
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
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .bSpline(sourceCurve()), surface: .bSpline(multiple),
                options: graphOptions(), tolerance: .standard)
        }
        let x = [0.0, 0, 0.5, 1.25], knots = [0.0, 0, 0, 0.5, 1, 1, 1]
        let corner = BSplineSurface3D(uDegree: 2, vDegree: 2, uKnots: knots, vKnots: knots,
            controlPoints: x.map { y in x.map { value in Point3D(x: value, y: y, z: value * y) } })
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .bSpline(sourceCurve()), surface: .bSpline(corner),
                options: graphOptions(), tolerance: .standard)
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
        #expect(proof.authority == .collar(axis: .u, knot: 0.5))
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
    func continuousNativeKnotAndTensorCornerRemainUnsupported() throws {
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
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .bSpline(sourceCurve()), surface: .bSpline(corner),
                options: graphOptions(), tolerance: .standard)
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
