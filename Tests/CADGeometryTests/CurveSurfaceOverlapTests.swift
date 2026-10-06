import CADCore
@testable import CADGeometry
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
    func numericalResourceFailuresAndIdentityChartImageRemainExplicit() throws {
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
        let result = try intersector.intersectionResult(curve: .surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: complex)),
            surface: surface, options: .init(surfaceURange: try ScalarInterval(lower: 0.3, upper: 0.7)), tolerance: .standard)
        let overlap = try #require(result.overlaps.first)
        #expect(result.overlaps.count == 1)
        #expect(abs(overlap.curveRange.lower - 0.25) < 1e-8)
        #expect(abs(overlap.curveRange.upper - 0.75) < 1e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalNonHostedIsocurvesOwnClippedCorrespondenceInBothDirections() throws {
        var patch = try #require(curvedPatchSpline())
        patch.weights = [[1, 2, 1], [1.5, 3, 1.5], [1, 2, 1]]
        let surface = Surface3D.bSpline(patch)
        for variesU in [true, false] {
            let native = variesU ? try patch.uIsoparametricCurve(atV: 0.5, tolerance: .standard)
                : try patch.vIsoparametricCurve(atU: 0.5, tolerance: .standard)
            for reversed in [false, true] {
                var source = reversed ? try native.reversed(tolerance: .standard) : native
                var options = CurveSurfaceIntersectionOptions(curveRange: try ScalarInterval(lower: 0.1, upper: 0.9))
                if variesU { options.surfaceURange = try ScalarInterval(lower: 0.2, upper: 0.6) }
                else { options.surfaceVRange = try ScalarInterval(lower: 0.2, upper: 0.6) }
                let result = try intersector.intersectionResult(curve: .bSpline(source), surface: surface,
                    options: options, tolerance: .standard)
                let overlap = try #require(result.overlaps.first)
                #expect(result.overlaps.count == 1 && result.points.isEmpty)
                #expect(abs(overlap.curveRange.lower - (reversed ? 0.4 : 0.2)) < 1e-8)
                #expect(abs(overlap.curveRange.upper - (reversed ? 0.8 : 0.6)) < 1e-8)
                #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
                let original = source
                source.controlPoints[0] = Point3D(x: 50, y: 50, z: 50)
                for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    let parameter = overlap.curveRange.lower + overlap.curveRange.width * fraction
                    let value = try overlap.correspondence(at: parameter)
                    let uv = value.surfaceParameter
                    #expect(abs((variesU ? uv.v : uv.u) - 0.5) < 1e-8)
                    #expect(abs((variesU ? uv.u : uv.v) - (reversed ? 1 - parameter : parameter)) < 1e-8)
                    #expect((try original.point(at: parameter, tolerance: .standard) - value.point).length < 1e-12)
                    #expect(value.residual <= ModelingTolerance.standard.distance)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonHostedIsocurveZeroWidthChartReturnsOneIsolatedPoint() throws {
        let patch = try #require(curvedPatchSpline())
        let source = try patch.uIsoparametricCurve(atV: 0.5, tolerance: .standard)
        let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(patch),
            options: .init(surfaceURange: try ScalarInterval(lower: 0.4, upper: 0.4)), tolerance: .standard)
        #expect(result.overlaps.isEmpty && result.points.count == 1)
        #expect(abs(try #require(result.points.first).curveParameter - 0.4) < 1e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func isocurveCertificateRejectsInteriorDeviationAndBudgetExhaustion() throws {
        let patch = try #require(curvedPatchSpline())
        var source = try patch.uIsoparametricCurve(atV: 0.5, tolerance: .standard)
        let range = try ScalarInterval(lower: 0, upper: 1)
        source.controlPoints[1] = source.controlPoints[1] + Vector3D(x: 0, y: 0, z: 0.1)
        let certificate = try OverlapIsoparametricMembershipCertifier().certificate(curve: source, surface: patch,
            range: range, options: .init(), tolerance: .standard)
        #expect(certificate == nil)
        let discrete = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(patch),
            options: .init(), tolerance: .standard)
        // The perturbation adds 0.2*t*(1-t) in Z. The target's XY chart is
        // injective, so equality occurs exactly at the two domain endpoints.
        #expect(discrete.overlaps.isEmpty && discrete.points.count == 2)
        for (point, expected) in zip(discrete.points, [0.0, 1.0]) {
            #expect(abs(point.curveParameter - expected) <= ModelingTolerance.standard.distance)
            #expect(point.residual <= ModelingTolerance.standard.distance)
            let sourcePoint = try source.point(at: point.curveParameter, tolerance: .standard)
            let targetPoint = try patch.point(u: point.surfaceU, v: point.surfaceV, tolerance: .standard)
            #expect((sourcePoint - targetPoint).length <= ModelingTolerance.standard.distance)
        }
        let exact = try patch.uIsoparametricCurve(atV: 0.5, tolerance: .standard)
        try expectFailure(.resourceLimitExceeded) {
            _ = try intersector.intersectionResult(curve: .bSpline(exact), surface: .bSpline(patch),
                options: .init(maximumSubdivisionCells: 2), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func largeShiftedReversedNativeChartsRetainTheirExactAffineDirection() throws {
        let lower = 18_014_398_509_481_984.0
        let upper = lower + 65_536
        let tolerance = ModelingTolerance(distance: 1e-6, angle: 1e-9, relative: 1e-18)
        for variesU in [true, false] {
            var patch = try #require(curvedPatchSpline())
            let knots = [lower, lower, lower, upper, upper, upper]
            if variesU { patch.uKnots = knots } else { patch.vKnots = knots }
            let native = variesU ? try patch.uIsoparametricCurve(atV: 0, tolerance: tolerance)
                : try patch.vIsoparametricCurve(atU: 0, tolerance: tolerance)
            let source = try native.reversed(tolerance: tolerance)
            var options = CurveSurfaceIntersectionOptions()
            let clip = try ScalarInterval(lower: lower + 16_384, upper: lower + 49_152)
            if variesU { options.surfaceURange = clip } else { options.surfaceVRange = clip }
            let map = OverlapIsoparametricCorrespondence(variesU: variesU, fixedCoordinate: 0,
                reversedParameterSum: lower + upper)
            // At this offset the previous coordinate difference is exactly zero.
            #expect(map.parameter(at: 0) == map.parameter(at: 1))
            let cuts = try map.boundarySourceParameters(uValues: variesU ? [clip.lower, clip.upper] : [],
                vValues: variesU ? [] : [clip.lower, clip.upper], surface: .bSpline(patch), tolerance: tolerance)
            #expect(cuts == [clip.upper, clip.lower])
            let result = try intersector.intersectionResult(curve: .bSpline(source), surface: .bSpline(patch),
                options: options, tolerance: tolerance)
            let overlap = try #require(result.overlaps.first)
            #expect(result.overlaps.count == 1 && result.points.isEmpty)
            #expect(overlap.curveRange == clip)
            for parameter in [clip.lower, lower + 32_768, clip.upper] {
                let value = try overlap.correspondence(at: parameter)
                #expect((variesU ? value.surfaceParameter.u : value.surfaceParameter.v) == lower + upper - parameter)
                #expect((variesU ? value.surfaceParameter.v : value.surfaceParameter.u) == 0)
                #expect(value.residual <= tolerance.distance)
            }
        }
        // A reversed wide chart cannot encode the inverse of 0.5 at its large
        // source endpoint. Its chart error exceeds the existing admission.
        var unresolvedPatch = try #require(curvedPatchSpline())
        unresolvedPatch.uKnots = [0, 0, 0, lower, lower, lower]
        let unresolved = OverlapIsoparametricCorrespondence(variesU: true, fixedCoordinate: 0,
            reversedParameterSum: lower)
        try expectFailure(.intersectionFailure) {
            _ = try unresolved.boundarySourceParameters(uValues: [0.5], vValues: [],
                surface: .bSpline(unresolvedPatch), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func restrictedReversedRigidChartImageIsClippedInItsOwnedParameter() throws {
        let surface = curvedPatch()
        let authored = SurfaceParameterCurve.affine(origin: Point2D(x: 0.1, y: 0.5),
            direction: Point2D(x: 0.8, y: 0), startParameter: 0, endParameter: 1)
        let image = try RigidImageSurfaceParameterCurve(source: SurfaceLiftCurve3D(surface: surface, parameterCurve: authored),
            targetSurface: surface, transform: .translated(by: .zero), startFraction: 0.9, endFraction: 0.1, tolerance: .standard)
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: .rigidImage(image)))
        let result = try intersector.intersectionResult(curve: curve, surface: surface,
            options: .init(surfaceURange: try ScalarInterval(lower: 0.3, upper: 0.7)), tolerance: .standard)
        let overlap = try #require(result.overlaps.first)
        #expect(result.overlaps.count == 1)
        #expect(abs(overlap.curveRange.lower - 0.1875) < 1e-8)
        #expect(abs(overlap.curveRange.upper - 0.8125) < 1e-8)
        #expect(abs(try overlap.correspondence(at: 0.5).surfaceParameter.u - 0.5) < 1e-12)
        try expectFailure(.resourceLimitExceeded) {
            _ = try intersector.intersectionResult(curve: curve, surface: surface,
                options: .init(maximumSubdivisionDepth: 0), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetChartImageUsesExactCoordinateTransferForClipping() throws {
        let source = curvedPatch()
        let offset = OffsetSurface3D(source: source, distance: 0.1)
        let image = try offset.parameterCurveImage(transporting: .affine(origin: Point2D(x: 0.1, y: 0.5),
            direction: Point2D(x: 0.8, y: 0), startParameter: 0, endParameter: 1), tolerance: .standard)
        let surface = try image.targetSurface(tolerance: .standard)
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: .offsetSurfaceImage(image)))
        let result = try intersector.intersectionResult(curve: curve, surface: surface,
            options: .init(surfaceURange: try ScalarInterval(lower: 0.3, upper: 0.7)), tolerance: .standard)
        let overlap = try #require(result.overlaps.first)
        #expect(result.overlaps.count == 1)
        #expect(abs(overlap.curveRange.lower - 0.25) < 1e-8)
        #expect(abs(overlap.curveRange.upper - 0.75) < 1e-8)
        #expect(try overlap.correspondence(at: 0.5).residual < 1e-12)
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

    private func curvedPatchSpline() -> BSplineSurface3D? {
        guard case .bSpline(let spline) = curvedPatch() else { return nil }
        return spline
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
