import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Public original native curve-surface isolated points", .serialized)
struct NativeCurveSurfacePointTests {
    private let tolerance = ModelingTolerance.standard

    private func plane() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1], controlPoints: [
            [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
            [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
    }

    private func weightedPlane() -> BSplineSurface3D {
        var surface = plane()
        surface.weights = [[1,2],[3,6]]
        return surface
    }

    private func weighted() -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.5, y: 0.5, z: -1), .init(x: 0.5, y: 0.5, z: 1)], weights: [1,2])
    }

    private func usage() throws -> OriginalQueryExecution {
        try .independentGeometry()
    }

    @Test(.timeLimit(.minutes(1)))
    func weightedExactTupleAndNormalSelectedDiscreteAgreement() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let curve = Curve3D.bSpline(weighted()), surface = Surface3D.bSpline(weightedPlane())
        let result = try solver.intersectionResult(curve: curve, surface: surface, tolerance: tolerance)
        let receipt = try #require(result.originalNativePoints)
        #expect(result.points.count == 1 && result.overlaps.isEmpty && receipt.count == 1)
        let point = try #require(result.points.first)
        #expect(abs(point.curveParameter - 1.0 / 3) < 1e-12)
        #expect(abs(point.surfaceU - 1.0 / 3) < 1e-12 && point.surfaceV == 0.25 && point.kind == .transverse)
        #expect(point.residual <= tolerance.distance)
        var admission = try usage()
        let third = try ExactRationalCoefficient.one.divided(by: .originalDouble(3, usage: &admission), usage: &admission)
        let tuple = try receipt.point(at: 0)
        #expect(try tuple.compareParameter(axis: 0, to: third, in: receipt,
            maximumAlgebraicDepth: 32, usage: &admission) == .zero)
        let exact = try tuple.parameter(axis: 0, in: receipt).enclosed(maximumDepth: 32,
            maximumCoefficientDepth: 0, usage: &admission)
        #expect(exact.lower == third && exact.upper == third)
        let work = Mutex(0), bytes = Mutex(0)
        let selected = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in work.withLock { $0 += 1 } },
            consumeStorageBytes: { value in bytes.withLock { $0 += value } }) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(selected.points == result.points)
        #expect(work.withLock { $0 } > 0 && bytes.withLock { $0 } > 0)
        print("Native two-axis weighted admitted work=\(work.withLock { $0 }) bytes=\(bytes.withLock { $0 })")
        #expect(try solver.intersections(curve: curve, surface: surface, options: .init(), tolerance: tolerance) == result.points)
        #expect(try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        } == result.points)
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedTangentAndClosedSingleton() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0, y: 0.5, z: 0.25), .init(x: 0.5, y: 0.5, z: -0.25), .init(x: 1, y: 0.5, z: 0.25)])
        let solver = DefaultCurveSurfaceIntersector()
        let whole = try solver.intersectionResult(curve: .bSpline(curve), surface: .bSpline(plane()), tolerance: tolerance)
        #expect(whole.points.count == 1 && whole.points.first?.kind == .tangent)
        let singleton = try ScalarInterval(lower: 0.5, upper: 0.5)
        let selected = try solver.intersectionResult(curve: .bSpline(curve), surface: .bSpline(plane()),
            options: .init(curveRange: singleton, surfaceURange: singleton, surfaceVRange: singleton), tolerance: tolerance)
        #expect(selected.points == whole.points)
        #expect(selected.originalNativePoints?.effectiveDomains?.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedNativeSurface() throws {
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 2, uKnots: [0,0,0,1,1,1], vKnots: [0,0,0,1,1,1], controlPoints: [
            [.init(x: 0,y: 0,z: 0), .init(x: 0.5,y: 0,z: 0), .init(x: 1,y: 0,z: 1)],
            [.init(x: 0,y: 0.5,z: 0), .init(x: 0.5,y: 0.5,z: 0), .init(x: 1,y: 0.5,z: 1)],
            [.init(x: 0,y: 1,z: 1), .init(x: 0.5,y: 1,z: 1), .init(x: 1,y: 1,z: 2)]])
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.5,y: 0.5,z: -1), .init(x: 0.5,y: 0.5,z: 2)])
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface), tolerance: tolerance)
        #expect(result.points.count == 1)
        #expect(result.points.first?.curveParameter == 0.5)
        #expect(result.points.first?.point == Point3D(x: 0.5, y: 0.5, z: 0.5))
    }

    @Test(.timeLimit(.minutes(1)))
    func multipleUVAtSameXYZRemainSeparateAndOrdered() throws {
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [-1,-1,-1,1,1,1], vKnots: [0,0,1,1], controlPoints: [
            [.init(x: 1,y: 0,z: 0), .init(x: -1,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
            [.init(x: 1,y: 1,z: 0), .init(x: -1,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.25,y: 0.5,z: -1), .init(x: 0.25,y: 0.5,z: 1)])
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface), tolerance: tolerance)
        #expect(result.points.count == 2 && result.originalNativePoints?.count == 2)
        #expect(result.points[0].point == result.points[1].point)
        #expect(result.points[0].curveParameter == result.points[1].curveParameter)
        #expect(result.points[0].surfaceU == -0.5 && result.points[1].surfaceU == 0.5)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface),
                options: .init(maximumCandidateCount: 1), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func closeOriginalRootsRemainSeparate() throws {
        var readerExecution = try usage()
        let epsilon = 1.0 / 1_048_576.0, square = epsilon * epsilon
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: 0.25 - square), .init(x: 0.5,y: 0.5,z: -0.25 - square), .init(x: 1,y: 0.5,z: 0.25 - square)])
        let largeTolerance = ModelingTolerance(distance: 1e-4, angle: 1e-9)
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve), surface: .bSpline(plane()), tolerance: largeTolerance)
        #expect(result.points.count == 2 && result.originalNativePoints?.count == 2)
        #expect(result.points[0].curveParameter < result.points[1].curveParameter)
        #expect(abs(result.points[0].curveParameter - (0.5 - epsilon)) < epsilon)
        #expect(abs(result.points[1].curveParameter - (0.5 + epsilon)) < epsilon)
        let receipt = try #require(result.originalNativePoints)
        for ordinal in 0..<receipt.count {
            let coordinate = try receipt.point(at: ordinal).parameter(axis: 1, in: receipt)
            let enclosure = try coordinate.enclosed(maximumDepth: 32, maximumCoefficientDepth: 0, usage: &readerExecution)
            var admission = try usage()
            let width = try enclosure.upper.subtracting(enclosure.lower, usage: &admission)
            let limit = try ExactRationalCoefficient.originalDouble(largeTolerance.distance, usage: &admission)
            #expect(try !width.subtracting(limit, usage: &admission).isPositive)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func emptyCoverageNativeExclusionAndBoundary() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let outside = try solver.intersectionResult(curve: .bSpline(weighted()), surface: .bSpline(plane()),
            options: .init(surfaceURange: .init(lower: 2, upper: 3)), tolerance: tolerance)
        #expect(outside.points.isEmpty && outside.originalNativePoints?.count == 0)
        #expect(outside.originalNativePoints?.effectiveDomains == nil)
        let noRoot = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.5,y: 0.5,z: 1), .init(x: 0.5,y: 0.5,z: 2)])
        let empty = try solver.intersectionResult(curve: .bSpline(noRoot), surface: .bSpline(plane()), tolerance: tolerance)
        #expect(empty.points.isEmpty && empty.originalNativePoints != nil)
        let endpoint = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 0,y: 0,z: 1)])
        let edge = try solver.intersectionResult(curve: .bSpline(endpoint), surface: .bSpline(plane()), tolerance: tolerance)
        #expect(edge.points.count == 1 && edge.points.first?.curveParameter == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func receiptLifetimeAndForeignIdentity() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let result = try solver.intersectionResult(curve: .bSpline(weighted()), surface: .bSpline(plane()), tolerance: tolerance)
        let receipt = try #require(result.originalNativePoints), handle = try receipt.point(at: 0)
        let foreign = try #require(solver.intersectionResult(curve: .bSpline(weighted()), surface: .bSpline(plane()), tolerance: tolerance).originalNativePoints)
        #expect(receipt.curve == weighted() && receipt.surface == plane())
        #expect(receipt.owns(handle) && !foreign.owns(handle))
        #expect(throws: GeometryConversionError.self) { try handle.parameter(axis: 0, in: foreign) }
        var admission = try usage()
        #expect(try handle.compareParameter(axis: 1, to: .originalDouble(0.5, usage: &admission),
            in: receipt, maximumAlgebraicDepth: 32, usage: &admission) == .zero)
    }

    @Test(.timeLimit(.minutes(1)))
    func positiveDimensionPublishesRichRelationAndRejectsDiscreteAPI() throws {
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: 0), .init(x: 1,y: 0.5,z: 0)])
        let solver = DefaultCurveSurfaceIntersector()
        let rich = try solver.intersectionResult(curve: .bSpline(curve), surface: .bSpline(plane()), tolerance: tolerance)
        #expect(rich.points.isEmpty && rich.originalNativeRelations?.components.count == 1)
        #expect(rich.hasPositiveDimensionalSolutions)
        do {
            _ = try solver.intersections(curve: .bSpline(curve), surface: .bSpline(plane()), options: .init(), tolerance: tolerance)
            Issue.record("Positive-dimensional original coverage was published as discrete points.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0,1,2,3])
    func callerAdmissionFailuresPropagate(mode: Int) throws {
        let solver = DefaultCurveSurfaceIntersector()
        let exhausted = KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: "Test admission exhausted.")
        #expect(throws: (any Error).self) {
            try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: mode == 2 ? 0 : 1,
            maximumAlgebraicDepth: mode == 3 ? 0 : 32,
            consumeWorkUnits: { _ in if mode == 0 { throw exhausted } },
            consumeStorageBytes: { _ in if mode == 1 { throw exhausted } }) { queryExecution in
            try solver.intersectionResult(curve: .bSpline(mode == 3
                ? BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
                    .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)])
                : weighted()),
            surface: .bSpline(plane()),
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func mixedDimensionalCoverageRejectsIsolatedSubset() throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1], controlPoints: [
            [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
            [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 1,z: 0)]])
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 0.5,y: 0.25,z: -0.25), .init(x: 1,y: 0.5,z: 0.5)])
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(curve: .bSpline(curve), surface: .bSpline(surface), options: .init(), tolerance: tolerance)
            Issue.record("Mixed-dimensional coverage published its isolated subset as discrete points.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
    }

    @Test(.timeLimit(.minutes(1)))
    func undefinedOriginalTangentIsMixed() throws {
        let curve = BSplineCurve3D(degree: 3, knots: [0,0,0,0,1,1,1,1], controlPoints: [
            .init(x: -0.125,y: 0.5,z: -0.125), .init(x: 0.125,y: 0.5,z: 0.125),
            .init(x: -0.125,y: 0.5,z: -0.125), .init(x: 0.125,y: 0.5,z: 0.125)])
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve), surface: .bSpline(plane()), tolerance: tolerance)
        #expect(result.points.count == 1 && result.points.first?.kind == .mixed)
    }

    @Test(.timeLimit(.minutes(1)))
    func optionWorkDegreeAndRefinementFailuresPropagate() throws {
        let solver = DefaultCurveSurfaceIntersector()
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try solver.intersectionResult(curve: .bSpline(weighted()), surface: .bSpline(plane()),
                options: .init(maximumSubdivisionCells: 1), tolerance: tolerance)
        }
        let irrational = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)])
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try solver.intersectionResult(curve: .bSpline(irrational), surface: .bSpline(plane()),
                options: .init(maximumPolynomialDegree: 1), tolerance: tolerance)
        }
        do {
            _ = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(curve: .bSpline(irrational),
            surface: .bSpline(plane()),
            options: .init(maximumIterations: 1),
            tolerance: tolerance,
            using: &queryExecution)
        }
            Issue.record("Unlocalized exact roots escaped the publication iteration limit.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
           
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.message.contains("publication exhausted refinement iterations"))
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func cancellationInFinalStorageAdmissionRejectsPublication(discrete: Bool, empty: Bool) async throws {
        let solver = DefaultCurveSurfaceIntersector()
        let curve = Curve3D.bSpline(weighted()), surface = Surface3D.bSpline(plane())
        let options = CurveSurfaceIntersectionOptions(
            surfaceURange: empty ? try ScalarInterval(lower: 2, upper: 3) : nil)
        @Sendable func query(_ consumeStorage: @escaping @Sendable (Int) throws -> Void) throws -> [CurveSurfaceIntersection] {
            if discrete {
                return try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: consumeStorage) { queryExecution in
            try solver.intersections(curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance,
            using: &queryExecution)
        }
            }
            let result = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: consumeStorage) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance,
            using: &queryExecution)
        }
            #expect(result.originalNativePoints?.count == (empty ? 0 : 1))
            return result.points
        }
        let total = Mutex(0)
        let baseline = try query { _ in total.withLock { $0 += 1 } }
        #expect(baseline.count == (empty ? 0 : 1))
        let finalCall = total.withLock { $0 }
        #expect(finalCall > 0)
        let visits = Mutex(0)
        let operation = Task {
            try query { _ in
                let count = visits.withLock { $0 += 1; return $0 }
                if count == finalCall { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await operation.value
            Issue.record("Cancellation in final native storage admission returned success.")
        } catch where geometryTestIsCancelled(error) {
            #expect(visits.withLock { $0 } == finalCall)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationInsideOriginalPreparationPropagates() async throws {
        let visits = Mutex(0)
        let curve = Curve3D.bSpline(weighted()), surface = Surface3D.bSpline(plane())
        let operation = Task {
            try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in
                    let count = visits.withLock { $0 += 1; return $0 }
                    if count == 20 { withUnsafeCurrentTask { $0?.cancel() } }
                },
            consumeStorageBytes: { _ in }) { queryExecution in
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve,
            surface: surface,
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
        do {
            _ = try await operation.value
            Issue.record("Cancelled original native preparation returned success.")
        } catch where geometryTestIsCancelled(error) { #expect(visits.withLock { $0 } >= 20) }
    }

    private func multiSpanCurve(spanCount: Int = 3) -> BSplineCurve3D {
        .init(degree: 1, knots: [0] + (0...spanCount).map(Double.init) + [Double(spanCount)],
            controlPoints: (0...spanCount).map { .init(x: 0.5, y: 0.5, z: $0.isMultiple(of: 2) ? -1 : 1) })
    }

    private func multiChartPlane() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,0.5,1,1], vKnots: [0,0,1,1], controlPoints: [
            [.init(x: 0,y: 0,z: 0), .init(x: 0.5,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
            [.init(x: 0,y: 1,z: 0), .init(x: 0.5,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
    }

    @Test(.timeLimit(.minutes(1)))
    func multiSpanPublicProductOrderAndAllFourRoutes() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let curve = Curve3D.bSpline(multiSpanCurve()), surface = Surface3D.bSpline(multiChartPlane())
        let result = try solver.intersectionResult(curve: curve, surface: surface, tolerance: tolerance)
        let receipt = try #require(result.originalNativePoints)
        #expect(receipt.count == 3 && result.points.map(\.curveParameter) == [0.5,1.5,2.5])
        #expect(result.points.allSatisfy { $0.surfaceU == 0.5 && $0.surfaceV == 0.5 })
        let selected = try geometryTestWithQuery(maximumSpanCount: 6,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(selected.points == result.points)
        #expect(try solver.intersections(curve: curve, surface: surface, options: .init(), tolerance: tolerance) == result.points)
        #expect(try geometryTestWithQuery(maximumSpanCount: 6,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        } == result.points)
        var admission = try usage()
        for ordinal in 0..<receipt.count {
            #expect(try receipt.point(at: ordinal).compareParameter(axis: 0,
                to: .originalDouble(Double(ordinal) + 0.5, usage: &admission), in: receipt,
                maximumAlgebraicDepth: 32, usage: &admission) == .zero)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [2,4])
    func twoAndMoreSpanCompleteReceipts(spanCount: Int) throws {
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(multiSpanCurve(spanCount: spanCount)),
            surface: .bSpline(plane()), tolerance: tolerance)
        let receipt = try #require(result.originalNativePoints)
        #expect(result.points.count == spanCount && receipt.coverageChartCount == spanCount)
        #expect(receipt.nativeDomains.count == 3 && receipt.nativeDomains == receipt.requestedDomains)
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedCurveKnotAndSurfaceCornerHaveOneSourceOwner() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,2,2,2], controlPoints: [
            .init(x: 0.5,y: 0.5,z: -1), .init(x: 0.5,y: 0.5,z: -0.5),
            .init(x: 0.5,y: 0.5,z: 0), .init(x: 0.5,y: 0.5,z: 0.5), .init(x: 0.5,y: 0.5,z: 1)])
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0,0,0.5,1,1], vKnots: [0,0,0.5,1,1],
            controlPoints: [0.0,0.5,1.0].map { y in [0.0,0.5,1.0].map { .init(x: $0,y: y,z: 0) } })
        let solver = DefaultCurveSurfaceIntersector()
        let whole = try solver.intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface), tolerance: tolerance)
        #expect(whole.points.count == 1 && whole.points.first?.curveParameter == 1)
        #expect(whole.originalNativePoints?.coverageChartCount == 8)
        let cut = try solver.intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface),
            options: .init(curveRange: .init(lower: 1,upper: 1), surfaceURange: .init(lower: 0.5,upper: 0.5),
                surfaceVRange: .init(lower: 0.5,upper: 0.5)), tolerance: tolerance)
        #expect(cut.points == whole.points && cut.originalNativePoints?.coverageChartCount == 8)
    }

    @Test(.timeLimit(.minutes(1)))
    func multiChartSameXYZDistinctUVUsesGlobalTupleOrder() throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [-1,-1,0,1,1], vKnots: [0,0,1,1], controlPoints: [
            [.init(x: 1,y: 0,z: 0), .init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
            [.init(x: 1,y: 1,z: 0), .init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(multiSpanCurve(spanCount: 2)),
            surface: .bSpline(surface), tolerance: tolerance)
        #expect(result.points.count == 4)
        #expect(result.points.map(\.curveParameter) == [0.5,0.5,1.5,1.5])
        #expect(result.points.map(\.surfaceU) == [-0.5,0.5,-0.5,0.5])
        #expect(result.points.allSatisfy { $0.point == result.points[0].point })
    }

    @Test(.timeLimit(.minutes(1)))
    func multiSpanEmptyAndRetainedSourceLifetime() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let retained: OriginalNativeCurveSurfacePoints
        do {
            let result = try solver.intersectionResult(curve: .bSpline(multiSpanCurve(spanCount: 2)),
                surface: .bSpline(multiChartPlane()), tolerance: tolerance)
            retained = try #require(result.originalNativePoints)
        }
        #expect(retained.coverageChartCount == 4 && retained.count == 2)
        var admission = try usage()
        #expect(try retained.point(at: 1).compareParameter(axis: 0,
            to: .originalDouble(1.5, usage: &admission), in: retained,
            maximumAlgebraicDepth: 32, usage: &admission) == .zero)
        let outside = try solver.intersectionResult(curve: .bSpline(multiSpanCurve(spanCount: 2)),
            surface: .bSpline(multiChartPlane()), options: .init(curveRange: .init(lower: 3,upper: 3)), tolerance: tolerance)
        #expect(outside.points.isEmpty && outside.originalNativePoints?.coverageChartCount == 4)
        #expect(outside.originalNativePoints?.effectiveDomains == nil)
        var source = multiSpanCurve(spanCount: 2)
        for index in source.controlPoints.indices { source.controlPoints[index].z = 1 }
        let empty = try solver.intersectionResult(curve: .bSpline(source), surface: .bSpline(multiChartPlane()), tolerance: tolerance)
        #expect(empty.points.isEmpty && empty.originalNativePoints?.coverageChartCount == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func laterPositiveDimensionalChartRejectsEarlierIsolatedPoint() throws {
        let source = BSplineCurve3D(degree: 1, knots: [0,0,1,2,3,3], controlPoints: [
            .init(x: 0.25,y: 0.5,z: -1), .init(x: 0.25,y: 0.5,z: 1),
            .init(x: 0.25,y: 0.5,z: 0), .init(x: 0.75,y: 0.5,z: 0)])
        let solver = DefaultCurveSurfaceIntersector()
        let result = try solver.intersectionResult(curve: .bSpline(source), surface: .bSpline(plane()), tolerance: tolerance)
        #expect(result.points.count == 1 && result.points[0].curveParameter == 0.5)
        #expect(result.originalNativeRelations?.components.count == 2)
        #expect(result.hasPositiveDimensionalSolutions)
        do {
            _ = try solver.intersections(curve: .bSpline(source), surface: .bSpline(plane()), options: .init(), tolerance: tolerance)
            Issue.record("A later positive-dimensional chart published an earlier isolated subset.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
    }

    @Test(.timeLimit(.minutes(1)))
    func multiSpanCeilingsAreCumulativeAndIndependent() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let curve = Curve3D.bSpline(multiSpanCurve(spanCount: 2)), surface = Surface3D.bSpline(multiChartPlane())
        #expect(throws: (any Error).self) {
            try geometryTestWithQuery(maximumSpanCount: 3,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try geometryTestWithQuery(maximumSpanCount: 4,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            options: .init(maximumCandidateCount: 1),
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try solver.intersectionResult(curve: curve, surface: surface,
                options: .init(maximumSubdivisionCells: 1), tolerance: tolerance)
        }
        let work = Mutex(0), bytes = Mutex(0)
        _ = try geometryTestWithQuery(maximumSpanCount: 4,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in work.withLock { $0 += 1 } },
            consumeStorageBytes: { n in bytes.withLock { $0 += n } }) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            tolerance: tolerance,
            using: &queryExecution)
        }
        let workCap = work.withLock { $0 } - 1, byteCap = bytes.withLock { $0 } - 1
        let exhausted = KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: "Cumulative test allowance exhausted.")
        for storage in [false,true] {
            let visits = Mutex(0)
            geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
                try geometryTestWithQuery(maximumSpanCount: 4,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in
                        if !storage, visits.withLock({ $0 += 1; return $0 > workCap }) { throw exhausted }
                    },
            consumeStorageBytes: { n in
                        if storage, visits.withLock({ $0 += n; return $0 > byteCap }) { throw exhausted }
                    }) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            tolerance: tolerance,
            using: &queryExecution)
        }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false,true])
    func multiSpanCancellationAfterChartSuccessOrFinalCallback(final: Bool) async throws {
        let curve = Curve3D.bSpline(multiSpanCurve(spanCount: 2)), surface = Surface3D.bSpline(plane())
        let solver = DefaultCurveSurfaceIntersector(), calls = Mutex(0)
        _ = try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in calls.withLock { $0 += 1 } }) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            tolerance: tolerance,
            using: &queryExecution)
        }
        let finalCall = calls.withLock { $0 }, visits = Mutex(0)
        // Both equal-size linear products have the same source cost; three quarters
        // of cumulative storage callbacks is after the first completed product.
        let stop = final ? finalCall : finalCall * 3 / 4
        let operation = Task {
            try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in
                    if visits.withLock({ $0 += 1; return $0 }) == stop { withUnsafeCurrentTask { $0?.cancel() } }
                }) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
        do { _ = try await operation.value; Issue.record("Cancelled multi-span query published a subset or success.") }
        catch where geometryTestIsCancelled(error) { #expect(visits.withLock { $0 } == stop) }
    }

    @Test(.timeLimit(.minutes(1)))
    func independentChartFieldsRetainTheSameIrrationalT() throws {
        var readerExecution = try usage()
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [-1,-1,-1,0,0,1,1,1], vKnots: [0,0,1,1], controlPoints: [
            [1.0,0,0,0,1].map { .init(x: $0,y: 0,z: 0) },
            [1.0,0,0,0,1].map { .init(x: $0,y: 1,z: 0) }])
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0.25,y: 0.5,z: -0.5), .init(x: 0.25,y: 0.5,z: -0.5), .init(x: 0.25,y: 0.5,z: 0.5)])
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface), tolerance: tolerance)
        #expect(result.points.count == 2 && result.originalNativePoints?.coverageChartCount == 2)
        #expect(result.points.map(\.surfaceU) == [-0.5,0.5])
        #expect(result.points.allSatisfy { abs($0.curveParameter - 0.5.squareRoot()) < tolerance.distance })
        let receipt = try #require(result.originalNativePoints)
        let first = try receipt.point(at: 0).parameter(axis: 0, in: receipt)
        let second = try receipt.point(at: 1).parameter(axis: 0, in: receipt)
        let a = try first.enclosed(maximumDepth: 32, maximumCoefficientDepth: 0, usage: &readerExecution)
        let b = try second.enclosed(maximumDepth: 32, maximumCoefficientDepth: 0, usage: &readerExecution)
        #expect(a.lower == b.lower && a.upper == b.upper)
        #expect(throws: (any Error).self) {
            try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 0,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve),
            surface: .bSpline(surface),
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func closeRootsOnOppositeNativeSpansRemainSeparate() throws {
        let epsilon = 1.0 / 1_048_576
        var source = multiSpanCurve(spanCount: 2)
        source.controlPoints[1].z = epsilon
        let largeTolerance = ModelingTolerance(distance: 1e-4, angle: 1e-9)
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(source), surface: .bSpline(plane()), tolerance: largeTolerance)
        #expect(result.points.count == 2)
        #expect(result.points[0].curveParameter < 1 && result.points[1].curveParameter > 1)
        #expect(result.points[1].curveParameter - result.points[0].curveParameter < largeTolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonClampedNativeSpansUseOriginalSourceBounds() throws {
        var source = multiSpanCurve(spanCount: 2)
        source.knots = [-1,0,1,2,3]
        var target = multiChartPlane()
        target.uKnots = [-0.5,0,0.5,1,1.5]
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(source), surface: .bSpline(target), tolerance: tolerance)
        #expect(result.points.map(\.curveParameter) == [0.5,1.5])
        #expect(result.originalNativePoints?.coverageChartCount == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func unadmittedDiscontinuousKnotRemainsExplicitFailure() throws {
        let source = BSplineCurve3D(degree: 1, knots: [0,0,1,1,2,2], controlPoints: [
            .init(x: 0.5,y: 0.5,z: -1), .init(x: 0.5,y: 0.5,z: 1),
            .init(x: 0.5,y: 0.5,z: -1), .init(x: 0.5,y: 0.5,z: 1)])
        #expect(throws: (any Error).self) {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(source), surface: .bSpline(plane()), tolerance: tolerance)
        }
    }

}
