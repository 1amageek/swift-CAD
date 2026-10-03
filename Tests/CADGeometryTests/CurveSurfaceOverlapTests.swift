import CADCore
import CADGeometry
import Testing

@Suite("Continuous curve-surface intersection results")
struct CurveSurfaceOverlapTests {
    private let intersector: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()

    @Test(.timeLimit(.minutes(1)))
    func fullPlanarOverlapReturnsEndpointsAndOwnedCorrespondence() throws {
        var curve = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        var surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let result = try intersector.intersectionResult(curve: curve, surface: surface,
            options: .init(curveRange: try ScalarInterval(lower: -2, upper: 3)), tolerance: .standard)
        #expect(result.points.isEmpty)
        let overlap = try #require(result.overlaps.first)
        #expect(result.overlaps.count == 1)
        #expect(overlap.curveRange.lower == -2)
        #expect(overlap.curveRange.upper == 3)
        #expect(overlap.start.point == Point3D(x: -2, y: 0, z: 0))
        #expect(overlap.end.point == Point3D(x: 3, y: 0, z: 0))
        #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        curve = .line(Line3D(origin: Point3D(x: 0, y: 0, z: 20), direction: .unitY))
        surface = .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 20), normal: .unitX))
        #expect(try overlap.correspondence(at: 0.25).point == Point3D(x: 0.25, y: 0, z: 0))
        #expect(throws: KernelError.self) { try overlap.correspondence(at: 4) }
    }

    @Test(.timeLimit(.minutes(1)))
    func partialRationalOverlapAndDiscreteEventsRemainComplete() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1,
            knots: [0, 0, 1, 2, 3, 4, 4],
            controlPoints: [Point3D(x: -2, y: 0, z: 0), Point3D(x: -1, y: 0, z: 0),
                            Point3D(x: 0, y: 0, z: 1), Point3D(x: 1, y: 0, z: -1), Point3D(x: 2, y: 0, z: 1)]))
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let result = try intersector.intersectionResult(curve: curve, surface: surface, options: .init(), tolerance: .standard)
        #expect(result.overlaps.count == 1)
        #expect(result.overlaps.first?.curveRange == (try ScalarInterval(lower: 0, upper: 1)))
        #expect(result.points.count == 2)
        #expect(abs(try #require(result.points.first).curveParameter - 2.5) < 1e-9)
        #expect(abs(try #require(result.points.last).curveParameter - 3.5) < 1e-9)
        try expectFailure(.nonDiscreteIntersection) {
            _ = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: surface, options: .init(), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func adjacentOverlapSpansMergeAndSeparatedSpansStaySeparate() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let joined = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 2, 2],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0), Point3D(x: 2, y: 0, z: 0)]))
        let joinedResult = try intersector.intersectionResult(curve: joined, surface: surface, options: .init(), tolerance: .standard)
        #expect(joinedResult.overlaps.count == 1)
        #expect(joinedResult.overlaps.first?.curveRange == (try ScalarInterval(lower: 0, upper: 2)))
        let separated = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 2, 3, 4, 4],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0), Point3D(x: 2, y: 0, z: 1),
                            Point3D(x: 3, y: 0, z: 0), Point3D(x: 4, y: 0, z: 0)]))
        let separatedResult = try intersector.intersectionResult(curve: separated, surface: surface, options: .init(), tolerance: .standard)
        #expect(separatedResult.overlaps.count == 2)
        #expect(separatedResult.points.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticChartClippingReturnsIntervalsAndIsolatedBoundaryPoints() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let direction = try surface.differentialGeometry(u: 0, v: 0, tolerance: .standard).tangentU
        let curve = Curve3D.line(Line3D(origin: .origin, direction: direction))
        let range = try ScalarInterval(lower: -1, upper: 1)
        let result = try intersector.intersectionResult(curve: curve, surface: surface,
            options: .init(curveRange: range, surfaceURange: try ScalarInterval(lower: -0.5, upper: 0.25)), tolerance: .standard)
        let overlap = try #require(result.overlaps.first)
        #expect(result.overlaps.count == 1)
        #expect(abs(overlap.curveRange.lower + 0.5) < 1e-9)
        #expect(abs(overlap.curveRange.upper - 0.25) < 1e-9)
        let pointResult = try intersector.intersectionResult(curve: curve, surface: surface,
            options: .init(curveRange: range, surfaceURange: try ScalarInterval(lower: 0, upper: 0)), tolerance: .standard)
        #expect(pointResult.overlaps.isEmpty)
        #expect(pointResult.points.count == 1)
        #expect(pointResult.points.first?.point == .origin)
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicCircleOverlapClipsAcrossTheTargetSeam() throws {
        let surface = Surface3D.analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 2))
        let curve = Curve3D.analytic(.circle(center: .origin, normal: .unitZ, radius: 2))
        let result = try intersector.intersectionResult(curve: curve, surface: surface,
            options: .init(curveRange: try ScalarInterval(lower: 5.5, upper: 7.5),
                           surfaceURange: try ScalarInterval(lower: 6, upper: 7)), tolerance: .standard)
        let overlap = try #require(result.overlaps.first)
        #expect(result.overlaps.count == 1)
        #expect(abs(overlap.curveRange.lower - 6) < 1e-8)
        #expect(abs(overlap.curveRange.upper - 7) < 1e-8)
        #expect(abs(overlap.start.surfaceParameter.u - 6) < 1e-8)
        #expect(abs(overlap.end.surfaceParameter.u - 7) < 1e-8)
        #expect(try overlap.correspondence(at: 6.5).residual < 1e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredFreeSurfaceOverlapClipsItsRetainedCoordinates() throws {
        let surface = curvedPatch()
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface,
            parameterCurve: .affine(origin: Point2D(x: 0.1, y: 0.5), direction: Point2D(x: 0.8, y: 0), startParameter: 0, endParameter: 1)))
        let result = try intersector.intersectionResult(curve: curve, surface: surface,
            options: .init(surfaceURange: try ScalarInterval(lower: 0.3, upper: 0.7)), tolerance: .standard)
        let overlap = try #require(result.overlaps.first)
        #expect(result.overlaps.count == 1)
        #expect(abs(overlap.curveRange.lower - 0.25) < 1e-8)
        #expect(abs(overlap.curveRange.upper - 0.75) < 1e-8)
        let correspondence = try overlap.correspondence(at: 0.5)
        #expect(abs(correspondence.surfaceParameter.u - 0.5) < 1e-12)
        #expect(correspondence.residual < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func singularPoleEndpointRetainsCoordinatesWithoutClaimingUniqueness() throws {
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface,
            parameterCurve: .constantU(u: 0.2, vStart: 0, vEnd: .pi / 2)))
        let result = try intersector.intersectionResult(curve: curve, surface: surface, options: .init(), tolerance: .standard)
        let overlap = try #require(result.overlaps.first)
        #expect(!overlap.start.isSurfaceChartSingular)
        #expect(overlap.end.isSurfaceChartSingular)
        #expect(overlap.end.surfaceParameter.u == 0.2)
        #expect(overlap.end.residual < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func affineBoundedPatchDoesNotAdmitOverlapOutsideItsDomain() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]]))
        let curve = Curve3D.line(Line3D(origin: Point3D(x: 0, y: 0.5, z: 0), direction: .unitX))
        let result = try intersector.intersectionResult(curve: curve, surface: surface,
            options: .init(curveRange: try ScalarInterval(lower: -2, upper: 3)), tolerance: .standard)
        #expect(result.overlaps.count == 1)
        #expect(result.overlaps.first?.curveRange == (try ScalarInterval(lower: 0, upper: 1)))
    }

    @Test(.timeLimit(.minutes(1)))
    func numericalResourceAndUnsupportedFailuresRemainDistinct() throws {
        let plane = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let near = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 1e-8), Point3D(x: 1, y: 0, z: 1e-8)]))
        try expectFailure(.intersectionFailure) {
            _ = try intersector.intersectionResult(curve: near, surface: plane, options: .init(),
                tolerance: ModelingTolerance(distance: 1e-10, angle: 1e-9, relative: 1e-4))
        }
        try expectFailure(.resourceLimitExceeded) {
            _ = try intersector.intersectionResult(curve: .line(Line3D(origin: .origin, direction: .unitX)), surface: plane,
                options: .init(curveRange: try ScalarInterval(lower: -1, upper: 1),
                               surfaceURange: try ScalarInterval(lower: -0.5, upper: 0.5), maximumCandidateCount: 2), tolerance: .standard)
        }
        let surface = curvedPatch()
        let authored = SurfaceParameterCurve.affine(origin: Point2D(x: 0.1, y: 0.5), direction: Point2D(x: 0.8, y: 0), startParameter: 0, endParameter: 1)
        let complex = SurfaceParameterCurve.rigidImage(try RigidImageSurfaceParameterCurve(
            source: SurfaceLiftCurve3D(surface: surface, parameterCurve: authored), targetSurface: surface,
            transform: .translated(by: .zero), tolerance: .standard))
        try expectFailure(.unsupportedCapability) {
            _ = try intersector.intersectionResult(curve: .surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: complex)),
                surface: surface, options: .init(), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func approximateHostingPlaneEqualityCannotAuthorizeWholeSpanOverlap() throws {
        let tolerance = ModelingTolerance.standard
        let source = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let tangentU = try source.differentialGeometry(u: 0, v: 0, tolerance: tolerance).tangentU
        let alpha = tolerance.angle / 2
        let length = 100 * tolerance.distance / alpha
        let targetNormal = try (Vector3D.unitZ + tangentU * alpha).normalized(tolerance: tolerance.distance)
        let target = Surface3D.plane(Plane3D(origin: .origin, normal: targetNormal))
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: source,
            parameterCurve: .harmonic(center: .init(x: 0, y: 0), cosine: .init(x: 0, y: 1),
                sine: .init(x: length, y: 0), startParameter: 0, endParameter: 2 * .pi)))
        for parameter in [0.0, 0.5, 1.0] {
            #expect(abs(try (curve.point(at: parameter, tolerance: tolerance) - .origin).dot(targetNormal)) <= tolerance.distance)
        }
        let quarterDistance = abs(try (curve.point(at: 0.25, tolerance: tolerance) - .origin).dot(targetNormal))
        #expect(quarterDistance > 99 * tolerance.distance)
        try expectFailure(.intersectionFailure) {
            _ = try intersector.intersectionResult(curve: curve, surface: target, options: .init(), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nearbyParallelHostingPlaneRequiresAndPassesWholeSpanDistanceProof() throws {
        let tolerance = ModelingTolerance.standard
        let source = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let target = Surface3D.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: tolerance.distance / 4), normal: .unitZ))
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: source,
            parameterCurve: .harmonic(center: .init(x: 0, y: 0), cosine: .init(x: 0, y: 1),
                sine: .init(x: 200_000, y: 0), startParameter: 0, endParameter: 2 * .pi)))
        let result = try intersector.intersectionResult(curve: curve, surface: target, options: .init(), tolerance: tolerance)
        let overlap = try #require(result.overlaps.first)
        #expect(result.overlaps.count == 1 && result.points.isEmpty)
        #expect(overlap.maximumSpatialDeviation >= tolerance.distance / 4)
        #expect(overlap.maximumSpatialDeviation < tolerance.distance / 2)
        for parameter in [0.0, 0.125, 0.25, 0.5, 0.75, 1.0] {
            #expect(try overlap.correspondence(at: parameter).residual <= overlap.maximumSpatialDeviation)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func isolatedMissInvalidRangeAndCancellationAreExplicit() async throws {
        let plane = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let crossing = Curve3D.line(Line3D(origin: Point3D(x: 0, y: 0, z: -1), direction: .unitZ))
        let range = try ScalarInterval(lower: 0, upper: 2)
        let result = try intersector.intersectionResult(curve: crossing, surface: plane, options: .init(curveRange: range), tolerance: .standard)
        #expect(result.overlaps.isEmpty)
        #expect(result.points.count == 1)
        let miss = try intersector.intersectionResult(curve: crossing, surface: plane,
            options: .init(curveRange: try ScalarInterval(lower: 2, upper: 3)), tolerance: .standard)
        #expect(miss.points.isEmpty && miss.overlaps.isEmpty)
        try expectFailure(.invalidInput) {
            _ = try intersector.intersectionResult(curve: crossing, surface: plane,
                options: .init(curveRange: try ScalarInterval(lower: 1, upper: 1)), tolerance: .standard)
        }
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in stream { break }
            return try intersector.intersectionResult(curve: crossing, surface: plane, options: .init(curveRange: range), tolerance: .standard)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func curvedPatch() -> Surface3D {
        .bSpline(BSplineSurface3D(uDegree: 2, vDegree: 2,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: (0..<3).map { v in (0..<3).map { u in
                Point3D(x: Double(u) / 2, y: Double(v) / 2, z: u == 1 && v == 1 ? 0.5 : 0)
            } }))
    }

    private func expectFailure(_ code: KernelErrorCode, _ operation: () throws -> Void) throws {
        do {
            try operation()
            Issue.record("The operation must explicitly reject this input.")
        } catch let error as KernelError {
            #expect(error.code == code)
        }
    }
}
