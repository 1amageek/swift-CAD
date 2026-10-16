import CADCore
@testable import CADGeometry
import Testing

@Suite("Original triangular affine closed charts")
struct OriginalTriangularClosedChartTests {
    private let intersector: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()

    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2, 3])
    func wholeOriginalTriangularChartRetainsLiteralInverseAndOwnership(mode: Int) throws {
        let reversed = mode == 1, swapped = mode == 2, signed = mode == 3
        var source = sourceCurve(reversed: reversed), target = targetSurface(swapped: swapped, signed: signed)
        let originalSource = source, originalTarget = target
        var options = graphOptions()
        options.curveRange = nil
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: options, tolerance: .standard)
        #expect(result.overlaps.count == 1 && result.points.isEmpty)
        let overlap = try #require(result.overlaps.first)
        #expect(overlap.curveRange == (try ScalarInterval(lower: 0, upper: 1)))
        #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        source.controlPoints[0].z = 2
        target.controlPoints[0][0].z = 3
        for t in [0.0, 0.125, 1.0 / 3, 0.75, 1.0] {
            let parameter = reversed ? 1-t : t, h = 2*parameter/(1+parameter)
            let u = signed ? 1-h : h, v = h
            let value = try overlap.correspondence(at: t)
            #expect(abs(value.surfaceParameter.u-u) < 1e-7 && abs(value.surfaceParameter.v-v) < 1e-7)
            let point = try originalSource.point(at: t, tolerance: .standard)
            let image = try originalTarget.point(u: value.surfaceParameter.u, v: value.surfaceParameter.v, tolerance: .standard)
            #expect((point-Point3D(x: h, y: 1.25*h, z: h*h)).length < 1e-12)
            #expect((point-image).length <= ModelingTolerance.standard.distance && value.residual <= ModelingTolerance.standard.distance)
        }
        let start = reversed ? 1.0 : 0, end = reversed ? 0.0 : 1
        #expect(overlap.start.surfaceParameter.u == (signed ? 1-start : start))
        #expect(overlap.start.surfaceParameter.v == start)
        #expect(overlap.end.surfaceParameter.u == (signed ? 1-end : end))
        #expect(overlap.end.surfaceParameter.v == end)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func triangularNativeClippingRetainsIndependentSourceEndpoints(reversed: Bool) throws {
        var options = graphOptions()
        options.curveRange = try ScalarInterval(lower: 0, upper: 1)
        options.surfaceURange = try ScalarInterval(lower: 0.25, upper: 0.75)
        options.surfaceVRange = options.surfaceURange
        let result = try intersector.intersectionResult(curve: .bSpline(sourceCurve(reversed: reversed)),
            surface: .bSpline(targetSurface()), options: options, tolerance: .standard)
        #expect(result.overlaps.count == 1 && result.points.isEmpty)
        let overlap = try #require(result.overlaps.first)
        let lower = reversed ? 2.0/5 : 1.0/7, upper = reversed ? 6.0/7 : 3.0/5
        #expect(abs(overlap.curveRange.lower-lower) < 1e-8 && abs(overlap.curveRange.upper-upper) < 1e-8)
        for t in [overlap.curveRange.lower, overlap.curveRange.midpoint, overlap.curveRange.upper] {
            let parameter = reversed ? 1-t : t, h = 2*parameter/(1+parameter)
            let value = try overlap.correspondence(at: t)
            #expect(abs(value.surfaceParameter.u-h) < 1e-7 && abs(value.surfaceParameter.v-h) < 1e-7)
            #expect(value.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0.0, 0.5, 1.0])
    func triangularNativeSingletonsRetainOriginalEndpointIncidence(boundary: Double) throws {
        var options = graphOptions()
        options.curveRange = try ScalarInterval(lower: 0, upper: 1)
        options.surfaceURange = try ScalarInterval(lower: boundary, upper: boundary)
        options.surfaceVRange = options.surfaceURange
        let result = try intersector.intersectionResult(curve: .bSpline(sourceCurve()), surface: .bSpline(targetSurface()),
            options: options, tolerance: .standard)
        #expect(result.overlaps.isEmpty && result.points.count == 1)
        let point = try #require(result.points.first)
        let expected = boundary == 0.5 ? 1.0/3 : boundary
        #expect(abs(point.curveParameter-expected) < 1e-8)
        #expect(abs(point.surfaceU-boundary) <= ModelingTolerance.standard.relative)
        #expect(abs(point.surfaceV-boundary) <= ModelingTolerance.standard.relative)
        #expect(point.residual <= ModelingTolerance.standard.distance)
        if boundary != 0.5 { #expect(point.curveParameter == expected && point.surfaceU == boundary && point.surfaceV == boundary) }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalTriangularPullbackPreservesCoupledPartialsAndExactFees() throws {
        let source = sourceCurve(), target = targetSurface()
        let axis = try ScalarInterval(lower: 0, upper: 1), box = SurfaceParameterBox(u: axis, v: axis)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard)
        let jet = try prepared.intervalJet(over: box, tolerance: .standard)
        #expect(jet.y.derivativeU.contains(0.25) && jet.y.derivativeU.lower > 0)
        // Existing original scan costs 35; seven target coefficient operations cost 7;
        // each of three pullback controls costs eight bounded exact operations.
        var options = graphOptions()
        options.maximumSubdivisionCells = 66
        var exactExecution = try OriginalQueryExecution.independentGeometry()
        let exact = try OverlapProofPolicy(options: options, tolerance: .standard, using: &exactExecution)
        let authority = try geometryTestRequire(OverlapRegularGraphClosedDomainAuthority.certificate(curve: .bSpline(source),
            surface: target, range: axis, pair: .init(first: 0, second: 1), box: box, target: jet, policy: exact, using: &exactExecution))
        let triangular: OverlapRegularGraphClosedDomainAuthority.Triangular?
        if case .triangular(let chart) = authority.mapping { triangular = chart } else { triangular = nil }
        let chart = try #require(triangular)
        #expect(chart.primaryCoordinate == 0 && chart.secondaryCoordinate == 1 && chart.primaryVariesU)
        #expect(try FloatingPointExpansion.sign(chart.shear) == .positive)
        #expect(authority.exactEndpoint(at: 0) == SurfaceParameter(u: 0, v: 0))
        #expect(authority.exactEndpoint(at: 1) == SurfaceParameter(u: 1, v: 1))
        try expectFailure(.resourceLimitExceeded) { try exact.work(using: &exactExecution) }
        options.maximumSubdivisionCells = 65
        var insufficientExecution = try OriginalQueryExecution.independentGeometry()
        let insufficient = try OverlapProofPolicy(options: options, tolerance: .standard, using: &insufficientExecution)
        try expectFailure(.resourceLimitExceeded) {
            _ = try OverlapRegularGraphClosedDomainAuthority.certificate(curve: .bSpline(source),
                surface: target, range: axis, pair: .init(first: 0, second: 1), box: box, target: jet, policy: insufficient, using: &insufficientExecution)
        }
        var preparationExecution = try OriginalQueryExecution.independentGeometry()
        let preparation = try OverlapProofPolicy(options: graphOptions(), tolerance: .standard, using: &preparationExecution)
        let independence = try geometryTestRequire(OverlapRegularGraphClosedDomainAuthority.TargetIndependence.certificate(
            prepared: prepared, policy: preparation, using: &preparationExecution))
        let retained = try independence.intersecting(jet, tolerance: .standard)
        #expect(retained.y.derivativeU.lower == jet.y.derivativeU.lower && retained.y.derivativeU.upper == jet.y.derivativeU.upper)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonAffineSingularAndOutsideOriginalPullbacksCannotMintExistence() throws {
        let source = sourceCurve(), target = targetSurface()
        let axis = try ScalarInterval(lower: 0, upper: 1), box = SurfaceParameterBox(u: axis, v: axis)
        var mixed = target
        mixed.controlPoints[1][1].y = mixed.controlPoints[1][1].y.nextUp
        var singular = target
        singular.controlPoints[1][0].y = 0
        singular.controlPoints[1][1].y = 0.25
        var outside = source
        outside.controlPoints[1].y = 1.125.nextUp
        for (curve, surface) in [(source, mixed), (source, singular), (outside, target)] {
            let jet = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
                .intervalJet(over: box, tolerance: .standard)
            var budgetExecution = try OriginalQueryExecution.independentGeometry()
            let budget = try OverlapProofPolicy(options: graphOptions(), tolerance: .standard, using: &budgetExecution)
            #expect(try OverlapRegularGraphClosedDomainAuthority.certificate(curve: .bSpline(curve),
                surface: surface, range: axis, pair: .init(first: 0, second: 1), box: box, target: jet, policy: budget, using: &budgetExecution) == nil)
        }
        var options = graphOptions()
        options.curveRange = axis
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(mixed), options: options, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unrepresentableOriginalCofactorProductsAreTypedRefusals() throws {
        let axis = try ScalarInterval(lower: 0, upper: 1), box = SurfaceParameterBox(u: axis, v: axis)
        for scale in [Double.leastNormalMagnitude, Double(sign: .plus, exponent: 1000, significand: 1)] {
            // Both diagonals are nonzero original inputs, although their product
            // underflows or overflows binary64. No rounded zero may certify rank.
            let target = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
                controlPoints: [[Point3D(x: 0,y: 0,z: 0),Point3D(x: scale,y: scale/4,z: 0)],
                                [Point3D(x: 0,y: scale,z: 0),Point3D(x: scale,y: scale+scale/4,z: 1)]])
            var source = sourceCurve()
            source.controlPoints = source.controlPoints.map { Point3D(x: $0.x*scale,y: $0.y*scale,z: $0.z) }
            let jet = try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard)
                .intervalJet(over: box, tolerance: .standard)
            var budgetExecution = try OriginalQueryExecution.independentGeometry()
            let budget = try OverlapProofPolicy(options: graphOptions(), tolerance: .standard, using: &budgetExecution)
            try expectFailure(.resourceLimitExceeded) {
                _ = try OverlapRegularGraphClosedDomainAuthority.certificate(curve: .bSpline(source), surface: target,
                    range: axis, pair: .init(first: 0,second: 1), box: box, target: jet, policy: budget, using: &budgetExecution)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func triangularInteriorDeviationCannotBecomeAnOverlap() throws {
        var source = sourceCurve()
        source.controlPoints[1].z += 0.125
        var options = graphOptions()
        options.curveRange = try ScalarInterval(lower: 0.1, upper: 0.8)
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(targetSurface()),
            options: options, tolerance: .standard)
        // XY uniquely fixes U=V=h; the independent positive residual is
        // .5*t*(1-t)/(1+t)^2 on the complete requested interior interval.
        #expect(result.overlaps.isEmpty && result.points.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func triangularOriginalComparisonPreservesCancellation() async throws {
        let source = sourceCurve(), target = targetSurface()
        let axis = try ScalarInterval(lower: 0, upper: 1), box = SurfaceParameterBox(u: axis, v: axis)
        let jet = try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard)
            .intervalJet(over: box, tolerance: .standard)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            var budgetExecution = try OriginalQueryExecution.independentGeometry()
            let budget = try OverlapProofPolicy(options: graphOptions(), tolerance: .standard, using: &budgetExecution)
            return try OverlapRegularGraphClosedDomainAuthority.certificate(curve: .bSpline(source), surface: target,
                range: axis, pair: .init(first: 0, second: 1), box: box, target: jet, policy: budget, using: &budgetExecution)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await geometryTestExpectFailure({ geometryTestIsCancelled($0) }) { _ = try await task.value }
    }

    private func sourceCurve(reversed: Bool = false) -> BSplineCurve3D {
        let points = [Point3D(x: 0,y: 0,z: 0),Point3D(x: 0.5,y: 0.625,z: 0),Point3D(x: 1,y: 1.25,z: 1)]
        return BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1],
            controlPoints: reversed ? Array(points.reversed()) : points, weights: reversed ? [4,2,1] : [1,2,4])
    }

    private func targetSurface(swapped: Bool = false, signed: Bool = false) -> BSplineSurface3D {
        let points: [[Point3D]]
        if signed {
            points = [[Point3D(x: 1,y: 0.25,z: 0),Point3D(x: 0,y: 0,z: 0)],
                      [Point3D(x: 1,y: 1.25,z: 1),Point3D(x: 0,y: 1,z: 0)]]
        } else {
            points = [[Point3D(x: 0,y: 0,z: 0),Point3D(x: 1,y: 0.25,z: 0)],
                      [Point3D(x: 0,y: 1,z: 0),Point3D(x: 1,y: 1.25,z: 1)]]
        }
        let controls = swapped ? [[points[0][0],points[1][0]],[points[0][1],points[1][1]]] : points
        return BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,1,1],vKnots: [0,0,1,1],controlPoints: controls)
    }

    private func graphOptions() -> CurveSurfaceIntersectionOptions {
        .init(maximumSubdivisionDepth: 20, maximumSubdivisionCells: 4_194_304, maximumCandidateCount: 16_384)
    }

    private func expectFailure(_ code: KernelErrorCode, _ operation: () throws -> Void) throws {
        do { try operation(); Issue.record("The original triangular chart must explicitly refuse this authority.") }
        catch {
            let published = OriginalQueryFailure.published(error, context: .unspecified, tolerance: .standard)
            #expect(OriginalQueryFailure.classification(of: published)?.code == code)
        }
    }
}
