import CADCore
@testable import CADGeometry
import Testing

@Suite("Original periodic native curve-surface overlaps")
struct PeriodicCurveSurfaceOverlapTests {
    private let intersector: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()

    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2, 3])
    func rationalDiamondOwnsWholeCycleAndBothFixedEndpoints(mode: Int) throws {
        let variesU = mode < 2, upper = mode % 2 == 1
        var source = try sourceCurve(upper: upper)
        var target = try targetSurface(variesU: variesU)
        let originalSource = source, originalTarget = target
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: .init(), tolerance: .standard)
        #expect(result.points.isEmpty && result.overlaps.count == 1)
        let overlap = try #require(result.overlaps.first)
        #expect(overlap.curveRange == (try ScalarInterval(lower: 0, upper: 4)))
        #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        source.controlPoints[0].z += 3
        target.controlPoints[0][0].z += 4
        for t in [0.0, 0.25, 0.75, 1, 2.5, 3.75, 4] {
            let station = try overlap.correspondence(at: t)
            let fixed = upper ? 1.0 : 0
            #expect(station.surfaceParameter.u == (variesU ? t : fixed))
            #expect(station.surfaceParameter.v == (variesU ? fixed : t))
            let expected = diamond(at: t, upper: upper)
            #expect((station.point - expected).length < 1e-12)
            #expect((try originalSource.point(at: t, tolerance: .standard) - expected).length < 1e-12)
            #expect((try originalTarget.point(u: station.surfaceParameter.u, v: station.surfaceParameter.v,
                tolerance: .standard) - expected).length <= ModelingTolerance.standard.distance)
            #expect(station.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func seamClipEnumeratesTranslatedBoundaryCopies(variesU: Bool) throws {
        let options = try options(range: (3.5, 4.5), varying: (-0.25, 0.25), variesU: variesU)
        let result = try query(variesU: variesU, options: options)
        #expect(result.overlaps.count == 1 && result.points.isEmpty)
        let overlap = try #require(result.overlaps.first)
        #expect(overlap.curveRange == (try ScalarInterval(lower: 3.75, upper: 4.25)))
        for t in [3.75, 4, 4.25] {
            let station = try overlap.correspondence(at: t)
            let coordinate = variesU ? station.surfaceParameter.u : station.surfaceParameter.v
            #expect(coordinate == t - 4)
            #expect((station.point - diamond(at: t)).length < 1e-12)
            #expect(station.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func roundedPeriodicCopiesRetainCompensatedBoundaryAdmission(reversed: Bool) throws {
        let source = reversed ? try sourceCurve().reversed(tolerance: .standard) : try sourceCurve()
        let bounds = reversed ? (-1.0, 1.0) : (3.5, 4.8)
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(targetSurface()),
            options: options(range: bounds, varying: (0.2, 0.6)), tolerance: .standard)
        #expect(result.overlaps.count == 1 && result.points.isEmpty)
        let overlap = try #require(result.overlaps.first)
        let lower = reversed ? -0.6 : 4.2, upper = reversed ? -0.2 : 4.6
        #expect(abs(overlap.curveRange.lower - lower) < 1e-12 && abs(overlap.curveRange.upper - upper) < 1e-12)
        for t in [overlap.curveRange.lower, overlap.curveRange.upper] {
            let value = try overlap.correspondence(at: t)
            #expect((value.point - diamond(at: reversed ? 4 - t : t)).length < 1e-12)
            #expect(value.surfaceParameter.u >= 0.2 - ModelingTolerance.standard.relative
                && value.surfaceParameter.u <= 0.6 + ModelingTolerance.standard.relative)
            #expect(value.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func periodicSingletonRetainsEveryFiniteSeamIncidence(variesU: Bool) throws {
        let result = try query(variesU: variesU,
            options: options(range: (-4, 8), varying: (0, 0), variesU: variesU))
        #expect(result.overlaps.isEmpty && result.points.count == 4)
        #expect(result.points.map(\.curveParameter) == [-4.0, 0, 4, 8])
        for point in result.points {
            #expect(point.point == Point3D(x: 1, y: 0, z: 0))
            #expect(point.surfaceU == 0 && point.surfaceV == 0)
            #expect(point.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func negativeCyclesAndCompleteTargetRangeKeepOriginalNativeMap(variesU: Bool) throws {
        let full = try query(variesU: variesU,
            options: options(range: (-4.5, 4.5), varying: (10, 14), variesU: variesU))
        #expect(full.points.isEmpty && full.overlaps.count == 1)
        let overlap = try #require(full.overlaps.first)
        #expect(overlap.curveRange == (try ScalarInterval(lower: -4.5, upper: 4.5)))
        for t in [-4.5, -4, -0.25, 0, 4, 4.5] {
            let station = try overlap.correspondence(at: t)
            let coordinate = variesU ? station.surfaceParameter.u : station.surfaceParameter.v
            #expect(coordinate >= 10 && coordinate <= 14)
            #expect((station.point - diamond(at: t)).length < 1e-12)
            #expect(station.residual <= ModelingTolerance.standard.distance)
        }
        let negative = try query(variesU: variesU,
            options: options(range: (-0.5, 0.5), varying: (-0.25, 0.25), variesU: variesU))
        #expect(negative.overlaps.first?.curveRange == (try ScalarInterval(lower: -0.25, upper: 0.25)))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func reversedCycleKeepsTheExactNativeReflection(variesU: Bool) throws {
        let source = try sourceCurve().reversed(tolerance: .standard)
        let target = try targetSurface(variesU: variesU)
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: options(range: (3.5, 4.5), varying: (-0.25, 0.25), variesU: variesU), tolerance: .standard)
        #expect(result.overlaps.count == 1 && result.points.isEmpty)
        let overlap = try #require(result.overlaps.first)
        #expect(overlap.curveRange == (try ScalarInterval(lower: 3.75, upper: 4.25)))
        for t in [3.75, 4, 4.25] {
            let station = try overlap.correspondence(at: t)
            let coordinate = variesU ? station.surfaceParameter.u : station.surfaceParameter.v
            #expect(coordinate == 4 - t)
            #expect((station.point - diamond(at: 4 - t)).length < 1e-12)
            #expect(station.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func exactIntegralOriginChangesPreserveTheNativeCycle(variesU: Bool) throws {
        let source = try sourceCurve().changingPeriodicOrigin(to: 4, tolerance: .standard)
        let target = try targetSurface(variesU: variesU).changingPeriodicOrigin(
            direction: variesU ? .u : .v, to: -4, tolerance: .standard)
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: options(range: (7.5, 8.5), varying: (-0.25, 0.25), variesU: variesU), tolerance: .standard)
        #expect(result.overlaps.first?.curveRange == (try ScalarInterval(lower: 7.75, upper: 8.25)))
        let overlap = try #require(result.overlaps.first)
        #expect((try overlap.correspondence(at: 8).point - diamond(at: 8)).length < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func wholeControlProofAndAllBoundaryCutsShareOneExactFee() throws {
        let source = try sourceCurve(), target = try targetSurface()
        let range = try ScalarInterval(lower: 3.5, upper: 4.5)
        var options = CurveSurfaceIntersectionOptions(curveRange: range)
        // 4*(5 source+15 target controls)+7 source+13 target knots+8 scalars=108.
        // First trial: 1 orientation+2 trial storage+24 basis/control work+1 owner=28.
        // Two boundary copies: 4 bounds+1 storage+3 inversion each=16.
        options.maximumSubdivisionCells = 152
        var budget = OverlapProofBudget(options: options, tolerance: .standard)
        let proof = try #require(OverlapIsoparametricMembershipCertifier().certificate(curve: source,
            surface: target, range: range, options: options, tolerance: .standard, budget: &budget))
        let cuts = try proof.correspondence.boundarySourceParameters(uValues: [-0.25, 0.25], vValues: [],
            surface: .bSpline(target), tolerance: .standard, budget: &budget)
        #expect(cuts == [3.75, 4.25])
        try expectFailure(.resourceLimitExceeded) { try budget.work() }
        options.maximumSubdivisionCells = 151
        var insufficient = OverlapProofBudget(options: options, tolerance: .standard)
        let retained = try #require(OverlapIsoparametricMembershipCertifier().certificate(curve: source,
            surface: target, range: range, options: options, tolerance: .standard, budget: &insufficient))
        try expectFailure(.resourceLimitExceeded) {
            _ = try retained.correspondence.boundarySourceParameters(uValues: [-0.25, 0.25], vValues: [],
                surface: .bSpline(target), tolerance: .standard, budget: &insufficient)
        }
        var storage = try self.options(range: (3.5, 4.5), varying: (-0.25, 0.25))
        storage.maximumCandidateCount = 4
        try expectFailure(.resourceLimitExceeded) { _ = try query(options: storage) }
    }

    @Test(.timeLimit(.minutes(1)))
    func changedOriginalCoefficientsTranslationsAndOriginsCannotMintMembership() throws {
        let source = try sourceCurve(), target = try targetSurface()
        var changed = source
        changed.controlPoints[2].z = 0.125
        var knots = source
        knots.knots[0] = knots.knots[0].nextUp
        let phase = try source.changingPeriodicOrigin(to: 0.125, tolerance: .standard)
        for candidate in [changed, knots, phase] {
            try expectFailure(.unsupportedCapability) {
                _ = try intersector.intersectionResult(curve: .bSpline(candidate), surface: .bSpline(target),
                    options: .init(curveRange: try ScalarInterval(lower: 3.5, upper: 4.5)), tolerance: .standard)
            }
        }
        var tail = source
        tail.controlPoints[4].x = 1.25
        try expectFailure(.invalidInput) {
            _ = try intersector.intersectionResult(curve: .bSpline(tail), surface: .bSpline(target), options: .init(), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func interiorFixedIsocurveRemainsAnExplicitUnsupportedFamily() throws {
        var source = try sourceCurve()
        source.controlPoints = source.controlPoints.map { Point3D(x: 1.125 * $0.x, y: 1.125 * $0.y, z: 0.25) }
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(targetSurface()),
                options: .init(), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unrepresentableBoundaryCyclesRefuseBeforeCutGrowth() throws {
        let lower = Double(sign: .plus, exponent: 56, significand: 1)
        try expectFailure(.resourceLimitExceeded) {
            _ = try query(options: options(range: (lower, lower + 16), varying: (-0.25, 0.25)))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicMembershipPropagatesPreCancellation() async throws {
        let source = try sourceCurve(), target = try targetSurface()
        let range = try ScalarInterval(lower: 3.5, upper: 4.5)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            let options = CurveSurfaceIntersectionOptions(curveRange: range)
            var budget = OverlapProofBudget(options: options, tolerance: .standard)
            return try OverlapIsoparametricMembershipCertifier().certificate(curve: source,
                surface: target, range: range, options: options, tolerance: .standard, budget: &budget)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        let options = CurveSurfaceIntersectionOptions(curveRange: range)
        var preparation = OverlapProofBudget(options: options, tolerance: .standard)
        let proof = try #require(OverlapIsoparametricMembershipCertifier().certificate(curve: source,
            surface: target, range: range, options: options, tolerance: .standard, budget: &preparation))
        let (cuts, cutContinuation) = AsyncStream<Void>.makeStream()
        let boundaryTask = Task {
            for await _ in cuts { break }
            var budget = OverlapProofBudget(options: options, tolerance: .standard)
            return try proof.correspondence.boundarySourceParameters(uValues: [-0.25, 0.25], vValues: [],
                surface: .bSpline(target), tolerance: .standard, budget: &budget)
        }
        boundaryTask.cancel()
        cutContinuation.yield()
        cutContinuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await boundaryTask.value }
    }

    private func query(variesU: Bool = true, options: CurveSurfaceIntersectionOptions) throws -> CurveSurfaceIntersectionResult {
        try intersector.intersectionResult(curve: .bSpline(sourceCurve()), surface: .bSpline(targetSurface(variesU: variesU)),
            options: options, tolerance: .standard)
    }

    private func options(range: (Double, Double), varying: (Double, Double),
                         variesU: Bool = true) throws -> CurveSurfaceIntersectionOptions {
        let source = try ScalarInterval(lower: range.0, upper: range.1)
        let target = try ScalarInterval(lower: varying.0, upper: varying.1)
        return .init(curveRange: source, surfaceURange: variesU ? target : nil, surfaceVRange: variesU ? nil : target)
    }

    private func sourceCurve(upper: Bool = false) throws -> BSplineCurve3D {
        let scale = upper ? 1.25 : 1.0, z = upper ? 1.0 : 0
        return try .periodic(degree: 1, cycleKnots: [0, 1, 2, 3, 4],
            controlPoints: [Point3D(x: scale, y: 0, z: z), Point3D(x: 0, y: scale, z: z),
                            Point3D(x: -scale, y: 0, z: z), Point3D(x: 0, y: -scale, z: z)],
            weights: [1, 2, 1, 2], tolerance: .standard)
    }

    private func targetSurface(variesU: Bool = true) throws -> BSplineSurface3D {
        let cycle = [(1.0, 0.0), (0, 1), (-1, 0), (0, -1)]
        let scale = [1.0, 1.125, 1.25], z = [0.0, 0, 1]
        let rows = (0..<3).map { row in cycle.map { Point3D(x: scale[row] * $0.0, y: scale[row] * $0.1, z: z[row]) } }
        let points = variesU ? rows : (0..<4).map { column in (0..<3).map { rows[$0][column] } }
        let weights = variesU ? Array(repeating: [1.0, 2, 1, 2], count: 3)
            : [1.0, 2, 1, 2].map { Array(repeating: $0, count: 3) }
        return try .periodic(uDegree: variesU ? 1 : 2, vDegree: variesU ? 2 : 1,
            uKnots: variesU ? [0, 1, 2, 3, 4] : [0, 0, 0, 1, 1, 1],
            vKnots: variesU ? [0, 0, 0, 1, 1, 1] : [0, 1, 2, 3, 4],
            controlPoints: points, weights: weights, isUPeriodic: variesU, isVPeriodic: !variesU, tolerance: .standard)
    }

    private func diamond(at t: Double, upper: Bool = false) -> Point3D {
        var phase = t.truncatingRemainder(dividingBy: 4)
        if phase < 0 { phase += 4 }
        let segment = Int(phase), local = phase - Double(segment)
        let controls = [(1.0, 0.0), (0, 1), (-1, 0), (0, -1), (1, 0)]
        let weights = [1.0, 2, 1, 2, 1]
        let first = (1 - local) * weights[segment], second = local * weights[segment + 1]
        let denominator = first + second, scale = upper ? 1.25 : 1.0
        return Point3D(x: scale * (first * controls[segment].0 + second * controls[segment + 1].0) / denominator,
            y: scale * (first * controls[segment].1 + second * controls[segment + 1].1) / denominator, z: upper ? 1 : 0)
    }

    private func expectFailure(_ code: KernelErrorCode, _ operation: () throws -> Void) throws {
        do { try operation(); Issue.record("The periodic isocurve must explicitly refuse unavailable authority.") }
        catch let error as KernelError { #expect(error.code == code) }
    }
}
