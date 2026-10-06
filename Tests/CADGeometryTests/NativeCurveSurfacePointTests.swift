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

    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in }, retainStorage: { _ in }, visitCell: { _ in }, visitCoefficientCell: { _ in })
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
        var admission = usage()
        let third = try ExactRationalCoefficient.one.divided(by: .originalDouble(3, usage: &admission), usage: &admission)
        let tuple = try receipt.point(at: 0)
        #expect(try tuple.compareParameter(axis: 0, to: third, in: receipt,
            maximumAlgebraicDepth: 32, usage: &admission) == .zero)
        let exact = try tuple.parameter(axis: 0, in: receipt).enclosed(maximumDepth: 32,
            maximumCoefficientDepth: 0, usage: admission)
        #expect(exact.lower == third && exact.upper == third)
        let work = Mutex(0), bytes = Mutex(0)
        let selected = try solver.intersectionResult(curve: curve, surface: surface, tolerance: tolerance,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { _ in work.withLock { $0 += 1 } },
            consumeStorage: { value in bytes.withLock { $0 += value } }, maximumAlgebraicDepth: 32)
        #expect(selected.points == result.points)
        #expect(work.withLock { $0 } > 0 && bytes.withLock { $0 } > 0)
        print("Native two-axis weighted admitted work=\(work.withLock { $0 }) bytes=\(bytes.withLock { $0 })")
        #expect(try solver.intersections(curve: curve, surface: surface, options: .init(), tolerance: tolerance) == result.points)
        #expect(try solver.intersections(curve: curve, surface: surface, options: .init(), tolerance: tolerance,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { _ in }, consumeStorage: { _ in }, maximumAlgebraicDepth: 32) == result.points)
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
        #expect(throws: KernelError.self) {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface),
                options: .init(maximumCandidateCount: 1), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func closeOriginalRootsRemainSeparate() throws {
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
            let enclosure = try coordinate.enclosed(maximumDepth: 32, maximumCoefficientDepth: 0, usage: usage())
            var admission = usage()
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
        var admission = usage()
        #expect(try handle.compareParameter(axis: 1, to: .originalDouble(0.5, usage: &admission),
            in: receipt, maximumAlgebraicDepth: 32, usage: &admission) == .zero)
    }

    @Test(.timeLimit(.minutes(1)))
    func positiveDimensionFailsBothPublicAPIs() throws {
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: 0), .init(x: 1,y: 0.5,z: 0)])
        let solver = DefaultCurveSurfaceIntersector()
        #expect(throws: KernelError.self) { try solver.intersectionResult(curve: .bSpline(curve), surface: .bSpline(plane()), tolerance: tolerance) }
        do {
            _ = try solver.intersections(curve: .bSpline(curve), surface: .bSpline(plane()), options: .init(), tolerance: tolerance)
            Issue.record("Positive-dimensional original coverage was published as discrete points.")
        } catch let error as KernelError { #expect(error.code == .nonDiscreteIntersection) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0,1,2,3])
    func callerAdmissionFailuresPropagate(mode: Int) throws {
        let solver = DefaultCurveSurfaceIntersector()
        let exhausted = KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: "Test admission exhausted.")
        #expect(throws: (any Error).self) {
            try solver.intersectionResult(curve: .bSpline(mode == 3
                ? BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
                    .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)])
                : weighted()), surface: .bSpline(plane()), tolerance: tolerance,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: mode == 2 ? 0 : 1,
                consumeWork: { _ in if mode == 0 { throw exhausted } },
                consumeStorage: { _ in if mode == 1 { throw exhausted } },
                maximumAlgebraicDepth: mode == 3 ? 0 : 32)
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
            _ = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface), tolerance: tolerance)
            Issue.record("Mixed-dimensional coverage published its isolated subset.")
        } catch let error as KernelError { #expect(error.code == .nonDiscreteIntersection) }
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
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(curve: .bSpline(weighted()), surface: .bSpline(plane()),
                options: .init(maximumSubdivisionCells: 1), tolerance: tolerance)
        }
        let irrational = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)])
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(curve: .bSpline(irrational), surface: .bSpline(plane()),
                options: .init(maximumPolynomialDegree: 1), tolerance: tolerance)
        }
        do {
            _ = try solver.intersectionResult(curve: .bSpline(irrational), surface: .bSpline(plane()),
                options: .init(maximumIterations: 1), tolerance: tolerance,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: { _ in }, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
            Issue.record("Unlocalized exact roots escaped the publication iteration limit.")
        } catch let error as KernelError {
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
                return try solver.intersections(curve: curve, surface: surface, options: options, tolerance: tolerance,
                    maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                    consumeWork: { _ in }, consumeStorage: consumeStorage, maximumAlgebraicDepth: 32)
            }
            let result = try solver.intersectionResult(curve: curve, surface: surface, options: options, tolerance: tolerance,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: { _ in }, consumeStorage: consumeStorage, maximumAlgebraicDepth: 32)
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
        } catch is CancellationError {
            #expect(visits.withLock { $0 } == finalCall)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationInsideOriginalPreparationPropagates() async throws {
        let visits = Mutex(0)
        let curve = Curve3D.bSpline(weighted()), surface = Surface3D.bSpline(plane())
        let operation = Task {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: surface, tolerance: tolerance,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: { _ in
                    let count = visits.withLock { $0 += 1; return $0 }
                    if count == 20 { withUnsafeCurrentTask { $0?.cancel() } }
                }, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
        }
        do {
            _ = try await operation.value
            Issue.record("Cancelled original native preparation returned success.")
        } catch is CancellationError { #expect(visits.withLock { $0 } >= 20) }
    }

}
