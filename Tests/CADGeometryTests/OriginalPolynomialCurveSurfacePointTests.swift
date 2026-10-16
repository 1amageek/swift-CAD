import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Public original Native curve and ruled isolated points", .serialized)
struct OriginalPolynomialCurveSurfacePointTests {
    private let tolerance = ModelingTolerance.standard

    private func plane(weighted: Bool = false) -> RuledSurface3D {
        let lower = BSplineCurve3D(degree: 1, knots: [2,2,4,4], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)], weights: weighted ? [1,2] : [1,1])
        let upper = BSplineCurve3D(degree: 1, knots: [2,2,4,4], controlPoints: [
            .init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)], weights: weighted ? [3,6] : [1,1])
        return .init(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper), uDomain: .closed(2,4))
    }

    private func vertical(weighted: Bool = false, x: Double = 0.5, y: Double = 0.5) -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: x,y: y,z: -1), .init(x: x,y: y,z: 1)], weights: weighted ? [1,2] : [1,1])
    }

    private func fold() -> RuledSurface3D {
        let a = BSplineCurve3D(degree: 2, knots: [-1,-1,-1,1,1,1], controlPoints: [
            .init(x: 1,y: 0,z: 0), .init(x: -1,y: 0,z: 0), .init(x: 1,y: 0,z: 0)])
        let b = BSplineCurve3D(degree: 2, knots: [-1,-1,-1,1,1,1], controlPoints: [
            .init(x: 1,y: 1,z: 0), .init(x: -1,y: 1,z: 0), .init(x: 1,y: 1,z: 0)])
        return .init(startBoundary: .bSpline(a), endBoundary: .bSpline(b), uDomain: .closed(-1,1))
    }

    private func usage() throws -> OriginalQueryExecution {
        try .independentGeometry()
    }

    private func admitted(curve: BSplineCurve3D, surface: RuledSurface3D,
        options: CurveSurfaceIntersectionOptions = .init()) throws -> CurveSurfaceIntersectionResult {
        let work = Mutex(0), bytes = Mutex(0)
        let result = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in work.withLock { $0 += 1 } },
            consumeStorageBytes: { amount in bytes.withLock { $0 += amount } }) { queryExecution in
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve),
            surface: .procedural(.ruled(surface)),
            options: options,
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(work.withLock { $0 } > 0 && bytes.withLock { $0 } > 0)
        print("Original curve/ruled admitted work=\(work.withLock { $0 }) bytes=\(bytes.withLock { $0 })")
        return result
    }

    @Test(.timeLimit(.minutes(2)))
    func weightedNonunitNativeDomainsUseAllPublicRoutes() throws {
        let solver = DefaultCurveSurfaceIntersector(), curve = vertical(weighted: true), surface = plane(weighted: true)
        let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.ruled(surface)), tolerance: tolerance)
        let receipt = try #require(result.originalPolynomialPoints), point = try #require(result.points.first)
        #expect(result.points.count == 1 && receipt.count == 1 && result.originalNativePoints == nil)
        #expect(receipt.curve == curve && receipt.surface == surface && receipt.coverageCellCount > 0)
        #expect(abs(point.curveParameter - 1.0 / 3) < 1e-9)
        #expect(abs(point.surfaceU - 8.0 / 3) < 1e-9 && point.surfaceV == 0.5)
        #expect(point.point == Point3D(x: 0.5,y: 0.5,z: 0) && point.kind == .transverse)
        #expect(point.residual <= tolerance.distance)
        #expect(try admitted(curve: curve, surface: surface).points == result.points)
        #expect(try solver.intersections(curve: .bSpline(curve), surface: .procedural(.ruled(surface)),
            options: .init(), tolerance: tolerance) == result.points)
        #expect(try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(curve: .bSpline(curve),
            surface: .procedural(.ruled(surface)),
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        } == result.points)
        var budget = try usage()
        let third = try ExactRationalCoefficient.one.divided(by: .originalDouble(3, usage: &budget), usage: &budget)
        let tuple = try receipt.point(at: 0)
        #expect(try tuple.compareParameter(axis: 0, to: third, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        let u = try ExactRationalCoefficient.originalDouble(8, usage: &budget).divided(by: .originalDouble(3, usage: &budget), usage: &budget)
        #expect(try tuple.compareParameter(axis: 1, to: u, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
    }

    @Test(.timeLimit(.minutes(2)))
    func multipleUVPreimagesRemainSeparateInExactTupleOrder() throws {
        let curve = vertical(x: 0.25), surface = fold(), solver = DefaultCurveSurfaceIntersector()
        let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.ruled(surface)), tolerance: tolerance)
        let receipt = try #require(result.originalPolynomialPoints)
        #expect(result.points.count == 2 && receipt.count == 2)
        #expect(result.points[0].point == result.points[1].point)
        #expect(result.points[0].curveParameter == result.points[1].curveParameter)
        #expect(result.points[0].surfaceU == -0.5 && result.points[1].surfaceU == 0.5)
        #expect(try admitted(curve: curve, surface: surface).points == result.points)
        var budget = try usage()
        for ordinal in 0..<2 {
            let station = try ExactRationalCoefficient.originalDouble(ordinal == 0 ? -0.5 : 0.5, usage: &budget)
            #expect(try receipt.point(at: ordinal).compareParameter(axis: 1, to: station,
                in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.ruled(surface)),
                options: .init(maximumCandidateCount: 1), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func repeatedTangentAndClosedCornerSingleton() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: 0.25), .init(x: 0.5,y: 0.5,z: -0.25), .init(x: 1,y: 0.5,z: 0.25)])
        let solver = DefaultCurveSurfaceIntersector()
        let tangent = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.ruled(plane())), tolerance: tolerance)
        #expect(tangent.points.count == 1 && tangent.points.first?.kind == .tangent)
        let endpoint = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 0,y: 0,z: 1)])
        let selected = CurveSurfaceIntersectionOptions(curveRange: try .init(lower: 0,upper: 0),
            surfaceURange: try .init(lower: 2,upper: 2), surfaceVRange: try .init(lower: 0,upper: 0))
        let corner = try solver.intersectionResult(curve: .bSpline(endpoint), surface: .procedural(.ruled(plane())),
            options: selected, tolerance: tolerance)
        #expect(corner.points.count == 1 && corner.points.first?.curveParameter == 0)
        #expect(corner.points.first?.surfaceU == 2 && corner.points.first?.surfaceV == 0)
        #expect(try admitted(curve: endpoint, surface: plane(), options: selected).points == corner.points)
    }

    @Test(.timeLimit(.minutes(2)))
    func completeEmptyCoverageAndDomainExclusion() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let noRoot = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.5,y: 0.5,z: 1), .init(x: 0.5,y: 0.5,z: 2)])
        let empty = try solver.intersectionResult(curve: .bSpline(noRoot), surface: .procedural(.ruled(plane())), tolerance: tolerance)
        let receipt = try #require(empty.originalPolynomialPoints)
        #expect(empty.points.isEmpty && receipt.count == 0 && receipt.coverageCellCount > 0 && receipt.effectiveDomains != nil)
        let outside = CurveSurfaceIntersectionOptions(surfaceURange: try .init(lower: 5,upper: 6))
        let excluded = try admitted(curve: vertical(), surface: plane(), options: outside)
        let proof = try #require(excluded.originalPolynomialPoints)
        #expect(excluded.points.isEmpty && proof.count == 0 && proof.effectiveDomains == nil)
        #expect(proof.requestedDomains.count == 3 && proof.nativeDomains.count == 3)
        #expect(try solver.intersections(curve: .bSpline(noRoot), surface: .procedural(.ruled(plane())), options: .init(), tolerance: tolerance).isEmpty)
    }

    @Test(.timeLimit(.minutes(2)), arguments: [false,true], [false,true])
    func positiveAndMixedFailAtomically(discrete: Bool, admitted: Bool) throws {
        let a = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)])
        let b = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 1,y: 1,z: 0)])
        let mixed = RuledSurface3D(startBoundary: .bSpline(a), endBoundary: .bSpline(b))
        let curves = [
            BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)]),
            BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
                .init(x: 0,y: 0,z: 0), .init(x: 0.5,y: 0.25,z: -0.25), .init(x: 1,y: 0.5,z: 0.5)])]
        let solver = DefaultCurveSurfaceIntersector()
        for curve in curves {
            do {
                if discrete {
                    if admitted {
                        _ = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(curve: .bSpline(curve),
            surface: .procedural(.ruled(mixed)),
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
                    } else { _ = try solver.intersections(curve: .bSpline(curve), surface: .procedural(.ruled(mixed)), options: .init(), tolerance: tolerance) }
                } else if admitted { _ = try self.admitted(curve: curve, surface: mixed) }
                else { _ = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.ruled(mixed)), tolerance: tolerance) }
                Issue.record("A positive or mixed original relation escaped the bounded isolated contract.")
            } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func releasedInputsRetainOriginalTupleAndRejectForeignOwner() throws {
        var readerExecution = try usage()
        let solver = DefaultCurveSurfaceIntersector()
        let receipt = try { () throws -> OriginalPolynomialCurveSurfacePoints in
            var curve = vertical(), surface = plane()
            let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.ruled(surface)), tolerance: tolerance)
            curve.controlPoints[0] = .init(x: 100,y: 100,z: 100)
            surface = plane(weighted: true)
            return try #require(result.originalPolynomialPoints)
        }()
        #expect(receipt.curve == vertical() && receipt.surface == plane())
        let handle = try receipt.point(at: 0)
        let foreign = try #require(solver.intersectionResult(curve: .bSpline(vertical()), surface: .procedural(.ruled(plane())), tolerance: tolerance).originalPolynomialPoints)
        #expect(receipt.owns(handle) && !foreign.owns(handle))
        #expect(throws: GeometryConversionError.self) { try handle.parameter(axis: 0, in: foreign) }
        let coordinate = try handle.parameter(axis: 1, in: receipt)
        let bounds = try coordinate.enclosed(maximumDepth: 32, maximumCoefficientDepth: 0, usage: &readerExecution)
        var budget = try usage()
        let three = try ExactRationalCoefficient.originalDouble(3, usage: &budget)
        #expect(bounds.lower == three && bounds.upper == three)
        #expect(try handle.compareParameter(axis: 1, to: three, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
    }

    @Test(.timeLimit(.minutes(2)), arguments: [0,1,2,3])
    func independentCallerAdmissionFailuresPropagate(mode: Int) throws {
        let exhausted = KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: "Test admission exhausted.")
        let irrational = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)])
        #expect(throws: (any Error).self) {
            try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: mode == 2 ? 0 : 1,
            maximumAlgebraicDepth: mode == 3 ? 0 : 32,
            consumeWorkUnits: { _ in if mode == 0 { throw exhausted } },
            consumeStorageBytes: { _ in if mode == 1 { throw exhausted } }) { queryExecution in
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(mode == 3 ? irrational : vertical()),
            surface: .procedural(.ruled(plane())),
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func sourceAndRefinementCeilingsRemainExplicit() throws {
        var readerExecution = try usage()
        let solver = DefaultCurveSurfaceIntersector()
        let irrational = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)])
        for options in [CurveSurfaceIntersectionOptions(maximumSubdivisionCells: 1),
            CurveSurfaceIntersectionOptions(maximumPolynomialDegree: 1),
            CurveSurfaceIntersectionOptions(maximumIterations: 1)] {
            geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
                try solver.intersectionResult(curve: .bSpline(irrational), surface: .procedural(.ruled(plane())),
                    options: options, tolerance: tolerance)
            }
        }
        let full = try solver.intersectionResult(curve: .bSpline(irrational), surface: .procedural(.ruled(plane())), tolerance: tolerance)
        let receipt = try #require(full.originalPolynomialPoints)
        let handle = try receipt.point(at: 0)
        var rejected = GeometryTestScalarRecorder(observeWork: { _ in
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: "Exact query work exhausted.")
        }, observeStorageWords: { _ in }, observeValueCell: { _ in }, observeCoefficientCell: { _ in })
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try handle.compareParameter(axis: 0, to: .zero, in: receipt, maximumAlgebraicDepth: 32, usage: &rejected)
        }
        #expect(throws: (any Error).self) {
            try handle.parameter(axis: 0, in: receipt).enclosed(maximumDepth: 0, maximumCoefficientDepth: 0, usage: &readerExecution)
        }
        let multi = BSplineCurve3D(degree: 1, knots: [0,0,0.5,1,1], controlPoints: [
            .init(x: 0.5,y: 0.5,z: -1), .init(x: 0.5,y: 0.5,z: 0), .init(x: 0.5,y: 0.5,z: 1)])
        do {
            _ = try solver.intersectionResult(curve: .bSpline(multi), surface: .procedural(.ruled(plane())), tolerance: tolerance)
            Issue.record("An uncomposed multiple-span curve escaped the bounded checkpoint.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .unsupportedCapability) }
    }

    @Test(.timeLimit(.minutes(2)), arguments: [false,true], [false,true])
    func finalStorageCancellationRejectsPointAndEmptyPublication(discrete: Bool, empty: Bool) async throws {
        let solver = DefaultCurveSurfaceIntersector(), curve = Curve3D.bSpline(vertical()), surface = Surface3D.procedural(.ruled(plane()))
        let options = CurveSurfaceIntersectionOptions(surfaceURange: empty ? try .init(lower: 5,upper: 6) : nil)
        @Sendable func query(_ storage: @escaping @Sendable (Int) throws -> Void) throws -> [CurveSurfaceIntersection] {
            if discrete {
                return try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: storage) { queryExecution in
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
            consumeStorageBytes: storage) { queryExecution in
            try solver.intersectionResult(curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance,
            using: &queryExecution)
        }
            #expect(result.originalPolynomialPoints?.count == (empty ? 0 : 1))
            return result.points
        }
        let baseline = Mutex(0)
        #expect(try query { _ in baseline.withLock { $0 += 1 } }.count == (empty ? 0 : 1))
        let finalCall = baseline.withLock { $0 }, visits = Mutex(0)
        let operation = Task {
            try query { _ in
                let ordinal = visits.withLock { $0 += 1; return $0 }
                if ordinal == finalCall { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await operation.value; Issue.record("Final cancellation returned a successful original polynomial receipt.") }
        catch where geometryTestIsCancelled(error) { #expect(visits.withLock { $0 } == finalCall) }
    }
}
