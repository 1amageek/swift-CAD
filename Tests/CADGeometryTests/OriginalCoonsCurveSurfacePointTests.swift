import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite("Public original Native curve and Coons isolated points", .serialized)
struct OriginalCoonsCurveSurfacePointTests {
    private let tolerance = ModelingTolerance(distance: 1e-6, angle: 1e-8)

    private func traversal(_ source: BSplineCurve3D, lower: Double, upper: Double,
        reversed: Bool = false, owner: Int? = nil, using admission: inout OriginalQueryExecution) throws -> OriginalCurveRootSpan3D {
        let root = try OriginalCurveRootSpan3D(source:.bSpline(source),start:.authored(lower),end:.authored(upper),
            nativeSpanIndex:owner,maximumParameterWidth:tolerance.relative,maximumSubdivisionDepth:0,
            tolerance:tolerance,usage:&admission,
            maximumSpanCount:4,remainingSourceDepth:0,maximumAlgebraicDepth:0)
        return reversed ? root.reversed() : root
    }

    private func coons(bottom: BSplineCurve3D, top: BSplineCurve3D,
        left: BSplineCurve3D, right: BSplineCurve3D, reversedBottom: Bool = false) throws -> OriginalCoonsSurface3D {
        var admission = try usage()
        return try .init(vMinimumBoundary:traversal(bottom,lower:bottom.knots[bottom.degree],
                upper:bottom.knots[bottom.controlPointCount],reversed:reversedBottom,using:&admission),
            vMaximumBoundary:traversal(top,lower:top.knots[top.degree],upper:top.knots[top.controlPointCount],using:&admission),
            uMinimumBoundary:traversal(left,lower:left.knots[left.degree],upper:left.knots[left.controlPointCount],using:&admission),
            uMaximumBoundary:traversal(right,lower:right.knots[right.degree],upper:right.knots[right.controlPointCount],using:&admission),
            tolerance:tolerance,using:&admission)
    }

    private func plane(weighted: Bool = false, multiple: Bool = false) throws -> OriginalCoonsSurface3D {
        let bottom = multiple
            ? BSplineCurve3D(degree:1,knots:[-2,-2,1,4,4],controlPoints:[
                .init(x:1,y:0,z:0),.init(x:0.5,y:0,z:0),.origin])
            : BSplineCurve3D(degree:1,knots:[-2,-2,4,4],controlPoints:[.init(x:1,y:0,z:0),.origin],
                weights:weighted ? [2,1] : [1,1])
        let top = BSplineCurve3D(degree:1,knots:[7,7,10,10],controlPoints:[
            .init(x:0,y:1,z:0),.init(x:1,y:1,z:0)],weights:weighted ? [1,2] : [1,1])
        let left = BSplineCurve3D(degree:1,knots:[1,1,5,5],controlPoints:[.origin,.init(x:0,y:1,z:0)],
            weights:weighted ? [3,3] : [1,1])
        let right = BSplineCurve3D(degree:1,knots:[-5,-5,-1,-1],controlPoints:[
            .init(x:1,y:0,z:0),.init(x:1,y:1,z:0)],weights:weighted ? [2,2] : [1,1])
        return try coons(bottom:bottom,top:top,left:left,right:right,reversedBottom:true)
    }

    private func vertical(weighted: Bool = false, x: Double = 0.5, y: Double = 0.5) -> BSplineCurve3D {
        .init(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:x,y:y,z:-1),.init(x:x,y:y,z:1)],
            weights:weighted ? [1,2] : [1,1])
    }

    private func fold() throws -> OriginalCoonsSurface3D {
        let bottom = BSplineCurve3D(degree:2,knots:[-2,-2,-2,4,4,4],controlPoints:[
            .init(x:1,y:0,z:0),.init(x:-1,y:0,z:0),.init(x:1,y:0,z:0)])
        let top = BSplineCurve3D(degree:2,knots:[7,7,7,10,10,10],controlPoints:[
            .init(x:1,y:1,z:0),.init(x:-1,y:1,z:0),.init(x:1,y:1,z:0)])
        let left = BSplineCurve3D(degree:1,knots:[1,1,5,5],controlPoints:[.init(x:1,y:0,z:0),.init(x:1,y:1,z:0)])
        let right = BSplineCurve3D(degree:1,knots:[-5,-5,-1,-1],controlPoints:left.controlPoints)
        return try coons(bottom:bottom,top:top,left:left,right:right)
    }

    private func usage() throws -> OriginalQueryExecution {
        try .independentGeometry()
    }

    private func admitted(curve: BSplineCurve3D, surface: OriginalCoonsSurface3D,
        options: CurveSurfaceIntersectionOptions = .init()) throws -> CurveSurfaceIntersectionResult {
        let work = Mutex(0), bytes = Mutex(0)
        let result = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in work.withLock { $0 += 1 } },
            consumeStorageBytes: { amount in bytes.withLock { $0 += amount } }) { queryExecution in
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve),
            surface: .procedural(.originalCoons(surface)),
            options: options,
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(work.withLock { $0 } > 0 && bytes.withLock { $0 } > 0)
        print("Original curve/Coons admitted work=\(work.withLock { $0 }) bytes=\(bytes.withLock { $0 })")
        return result
    }

    @Test(.timeLimit(.minutes(2)))
    func weightedNonunitNativeDomainsUseAllPublicRoutes() throws {
        let solver = DefaultCurveSurfaceIntersector(), surface = try plane(weighted: true)
        var curve = vertical(weighted:true); curve.knots = [-2,-2,4,4]
        let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalCoons(surface)), tolerance: tolerance)
        let receipt = try #require(result.originalCoonsPoints), point = try #require(result.points.first)
        #expect(result.points.count == 1 && receipt.count == 1 && result.originalNativePoints == nil)
        #expect(receipt.curve == curve && receipt.surface == surface && receipt.coverageCellCount > 0)
        #expect(abs(point.curveParameter) < 1e-9)
        #expect(abs(point.surfaceU - 1.0 / 3) < 1e-9 && point.surfaceV == 0.5)
        #expect(point.point == Point3D(x: 0.5,y: 0.5,z: 0) && point.kind == .transverse)
        #expect(point.residual <= tolerance.distance)
        #expect(try admitted(curve: curve, surface: surface).points == result.points)
        #expect(try solver.intersections(curve: .bSpline(curve), surface: .procedural(.originalCoons(surface)),
            options: .init(), tolerance: tolerance) == result.points)
        #expect(try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(curve: .bSpline(curve),
            surface: .procedural(.originalCoons(surface)),
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        } == result.points)
        var budget = try usage()
        let zero = ExactRationalCoefficient.zero
        let tuple = try receipt.point(at: 0)
        #expect(try tuple.compareParameter(axis: 0, to: zero, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        let u = try ExactRationalCoefficient.one.divided(by: .originalDouble(3, usage: &budget), usage: &budget)
        #expect(try tuple.compareParameter(axis: 1, to: u, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        let boundaries = receipt.source.coons.boundaries
        #expect(boundaries.count == 4 && receipt.source.coons.originalAtlas.cells.count == 1)
        #expect(boundaries[0].traversal == surface.vMinimumBoundary && boundaries[0].nativeSpanIndex == 1)
        let normalized = [u,u,try ExactRationalCoefficient.originalDouble(0.5,usage:&budget),
            try ExactRationalCoefficient.originalDouble(0.5,usage:&budget)]
        let originalStations = [2.0,8,3,-3]
        for index in 0..<4 {
            let map = boundaries[index].parameterMap
            let station = try map.gain.multiplied(by:normalized[index],usage:&budget).adding(map.offset,usage:&budget)
            let expected = try ExactRationalCoefficient.originalDouble(originalStations[index],usage:&budget)
            #expect(station == expected)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func multipleUVPreimagesRemainSeparateInExactTupleOrder() throws {
        let curve = vertical(x: 0.25), surface = try fold(), solver = DefaultCurveSurfaceIntersector()
        let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalCoons(surface)), tolerance: tolerance)
        let receipt = try #require(result.originalCoonsPoints)
        #expect(result.points.count == 2 && receipt.count == 2)
        #expect(result.points[0].point == result.points[1].point)
        #expect(result.points[0].curveParameter == result.points[1].curveParameter)
        #expect(result.points[0].surfaceU == 0.25 && result.points[1].surfaceU == 0.75)
        #expect(try admitted(curve: curve, surface: surface).points == result.points)
        var budget = try usage()
        for ordinal in 0..<2 {
            let station = try ExactRationalCoefficient.originalDouble(ordinal == 0 ? 0.25 : 0.75, usage: &budget)
            #expect(try receipt.point(at: ordinal).compareParameter(axis: 1, to: station,
                in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalCoons(surface)),
                options: .init(maximumCandidateCount: 1), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func repeatedTangentAndClosedCornerSingleton() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: 0.25), .init(x: 0.5,y: 0.5,z: -0.25), .init(x: 1,y: 0.5,z: 0.25)])
        let solver = DefaultCurveSurfaceIntersector()
        let tangent = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalCoons(plane())), tolerance: tolerance)
        #expect(tangent.points.count == 1 && tangent.points.first?.kind == .tangent)
        let endpoint = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 0,y: 0,z: 1)])
        let selected = CurveSurfaceIntersectionOptions(curveRange: try .init(lower: 0,upper: 0),
            surfaceURange: try .init(lower: 0,upper: 0), surfaceVRange: try .init(lower: 0,upper: 0))
        let corner = try solver.intersectionResult(curve: .bSpline(endpoint), surface: .procedural(.originalCoons(plane())),
            options: selected, tolerance: tolerance)
        #expect(corner.points.count == 1 && corner.points.first?.curveParameter == 0)
        #expect(corner.points.first?.surfaceU == 0 && corner.points.first?.surfaceV == 0)
        #expect(try admitted(curve: endpoint, surface: plane(), options: selected).points == corner.points)
    }

    @Test(.timeLimit(.minutes(2)))
    func completeEmptyCoverageAndDomainExclusion() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let noRoot = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.5,y: 0.5,z: 1), .init(x: 0.5,y: 0.5,z: 2)])
        let empty = try solver.intersectionResult(curve: .bSpline(noRoot), surface: .procedural(.originalCoons(plane())), tolerance: tolerance)
        let receipt = try #require(empty.originalCoonsPoints)
        #expect(empty.points.isEmpty && receipt.count == 0 && receipt.coverageCellCount > 0 && receipt.effectiveDomains != nil)
        let outside = CurveSurfaceIntersectionOptions(surfaceURange: try .init(lower: 5,upper: 6))
        let excluded = try admitted(curve: vertical(), surface: plane(), options: outside)
        let proof = try #require(excluded.originalCoonsPoints)
        #expect(excluded.points.isEmpty && proof.count == 0 && proof.effectiveDomains == nil)
        #expect(proof.requestedDomains.count == 3 && proof.nativeDomains.count == 3)
        #expect(try solver.intersections(curve: .bSpline(noRoot), surface: .procedural(.originalCoons(plane())), options: .init(), tolerance: tolerance).isEmpty)
    }

    @Test(.timeLimit(.minutes(2)), arguments: [false,true], [false,true])
    func positiveAndMixedFailAtomically(discrete: Bool, admitted: Bool) throws {
        let bottom = BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:0,z:0)])
        let top = BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:1,z:0)])
        let left = BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.origin])
        let right = BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:1,y:0,z:0),.init(x:1,y:1,z:0)])
        let mixed = try coons(bottom:bottom,top:top,left:left,right:right)
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
            surface: .procedural(.originalCoons(mixed)),
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
                    } else { _ = try solver.intersections(curve: .bSpline(curve), surface: .procedural(.originalCoons(mixed)), options: .init(), tolerance: tolerance) }
                } else if admitted { _ = try self.admitted(curve: curve, surface: mixed) }
                else { _ = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalCoons(mixed)), tolerance: tolerance) }
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
        let receipt = try { () throws -> OriginalCoonsCurveSurfacePoints in
            var curve = vertical(), surface = try plane()
            let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalCoons(surface)), tolerance: tolerance)
            curve.controlPoints[0] = .init(x: 100,y: 100,z: 100)
            surface = try plane(weighted: true)
            return try #require(result.originalCoonsPoints)
        }()
        let original = try plane()
        #expect(receipt.curve == vertical() && receipt.surface == original)
        let handle = try receipt.point(at: 0)
        let foreign = try #require(solver.intersectionResult(curve: .bSpline(vertical()), surface: .procedural(.originalCoons(plane())), tolerance: tolerance).originalCoonsPoints)
        #expect(receipt.owns(handle) && !foreign.owns(handle))
        #expect(throws: GeometryConversionError.self) { try handle.parameter(axis: 0, in: foreign) }
        let coordinate = try handle.parameter(axis: 1, in: receipt)
        let bounds = try coordinate.enclosed(maximumDepth: 32, maximumCoefficientDepth: 0, usage: &readerExecution)
        var budget = try usage()
        let half = try ExactRationalCoefficient.originalDouble(0.5, usage: &budget)
        #expect(bounds.lower == half && bounds.upper == half)
        #expect(try handle.compareParameter(axis: 1, to: half, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
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
            surface: .procedural(.originalCoons(plane())),
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
                try solver.intersectionResult(curve: .bSpline(irrational), surface: .procedural(.originalCoons(plane())),
                    options: options, tolerance: tolerance)
            }
        }
        let full = try solver.intersectionResult(curve: .bSpline(irrational), surface: .procedural(.originalCoons(plane())), tolerance: tolerance)
        let receipt = try #require(full.originalCoonsPoints)
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
            _ = try solver.intersectionResult(curve: .bSpline(multi), surface: .procedural(.originalCoons(plane())), tolerance: tolerance)
            Issue.record("An uncomposed multiple-span curve escaped the bounded checkpoint.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .unsupportedCapability) }
    }

    @Test(.timeLimit(.minutes(2)), arguments: [false,true], [false,true])
    func finalStorageCancellationRejectsPointAndEmptyPublication(discrete: Bool, empty: Bool) async throws {
        let solver = DefaultCurveSurfaceIntersector(), curve = Curve3D.bSpline(vertical()), surface = try Surface3D.procedural(.originalCoons(plane()))
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
            #expect(result.originalCoonsPoints?.count == (empty ? 0 : 1))
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
        do { _ = try await operation.value; Issue.record("Final cancellation returned a successful original Coons receipt.") }
        catch where geometryTestIsCancelled(error) { #expect(visits.withLock { $0 } == finalCall) }
    }

    @Test(.timeLimit(.minutes(2)))
    func closeDistinctOriginalRootsAreNotMergedByModelingTolerance() throws {
        // Both epsilon squared and the resulting original controls are exact dyadics.
        let epsilon = 0x1p-24
        let constant = 0.25 - epsilon * epsilon
        let curve = BSplineCurve3D(degree:2,knots:[0,0,0,1,1,1],controlPoints:[
            .init(x:0,y:0.5,z:constant),.init(x:0.5,y:0.5,z:-0.25-epsilon*epsilon),
            .init(x:1,y:0.5,z:constant)])
        let surface = try plane(), solver = DefaultCurveSurfaceIntersector()
        let result = try solver.intersectionResult(curve:.bSpline(curve),surface:.procedural(.originalCoons(surface)),tolerance:tolerance)
        let receipt = try #require(result.originalCoonsPoints)
        #expect(result.points.count == 2 && receipt.count == 2)
        #expect(result.points[0].curveParameter < result.points[1].curveParameter)
        #expect(result.points[1].curveParameter - result.points[0].curveParameter < tolerance.distance)
        var admission = try usage()
        for ordinal in 0..<2 {
            let station = try ExactRationalCoefficient.originalDouble(0.5 + (ordinal == 0 ? -epsilon : epsilon),usage:&admission)
            let tuple = try receipt.point(at:ordinal)
            #expect(try tuple.compareParameter(axis:0,to:station,in:receipt,maximumAlgebraicDepth:32,usage:&admission) == .zero)
            #expect(try tuple.compareParameter(axis:1,to:station,in:receipt,maximumAlgebraicDepth:32,usage:&admission) == .zero)
        }
        #expect(try admitted(curve:curve,surface:surface).points == result.points)
    }

    @Test(.timeLimit(.minutes(2)))
    func undefinedOriginalNormalKeepsExistingMixedClassification() throws {
        let surface = try fold(), solver = DefaultCurveSurfaceIntersector(), curve = vertical(x:0)
        let result = try solver.intersectionResult(curve:.bSpline(curve),surface:.procedural(.originalCoons(surface)),tolerance:tolerance)
        let receipt = try #require(result.originalCoonsPoints), point = try #require(result.points.first)
        #expect(receipt.count == 1 && point.surfaceU == 0.5 && point.surfaceV == 0.5 && point.kind == .mixed)
        #expect(try admitted(curve:curve,surface:surface).points == result.points)
    }

    @Test(.timeLimit(.minutes(2)), arguments: [0,1,2,3])
    func unsupportedCurveAndBoundarySourcesCannotFallBack(route: Int) throws {
        let multi = BSplineCurve3D(degree:1,knots:[0,0,0.5,1,1],controlPoints:[
            .init(x:0.5,y:0.5,z:-1),.init(x:0.5,y:0.5,z:0),.init(x:0.5,y:0.5,z:1)])
        let periodic = BSplineCurve3D(degree:1,knots:[-1,0,1,2,3],controlPoints:[
            .init(x:0.5,y:0.5,z:-1),.init(x:0.5,y:0.5,z:1),.init(x:0.5,y:0.5,z:-1)],isPeriodic:true)
        let surface = try plane(), boundaries = try plane(multiple:true)
        let inputs = [(multi,surface),(periodic,surface),(vertical(),boundaries)]
        let solver = DefaultCurveSurfaceIntersector()
        for (curve,source) in inputs {
            do {
                switch route {
                case 0: _ = try solver.intersectionResult(curve:.bSpline(curve),surface:.procedural(.originalCoons(source)),tolerance:tolerance)
                case 1: _ = try admitted(curve:curve,surface:source)
                case 2: _ = try solver.intersections(curve:.bSpline(curve),surface:.procedural(.originalCoons(source)),options:.init(),tolerance:tolerance)
                default: _ = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(curve:.bSpline(curve),
            surface:.procedural(.originalCoons(source)),
            options:.init(),
            tolerance:tolerance,
            using: &queryExecution)
        }
                }
                Issue.record("An unsupported original Coons query returned a legacy or partial success.")
            } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .unsupportedCapability) }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func originalSourceDegreeAndCertificationToleranceAreRetained() throws {
        let solver = DefaultCurveSurfaceIntersector(), surface = try fold(), curve = vertical()
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try solver.intersectionResult(curve:.bSpline(curve),surface:.procedural(.originalCoons(surface)),
                options:.init(maximumPolynomialDegree:1),tolerance:tolerance)
        }
        let incompatible = ModelingTolerance(distance:tolerance.distance / 2,angle:tolerance.angle)
        #expect(throws: GeometryConversionError.self) {
            try solver.intersectionResult(curve:.bSpline(curve),surface:.procedural(.originalCoons(surface)),tolerance:incompatible)
        }
        var invalid = curve; invalid.weights[0] = 0
        #expect(throws: GeometryError.self) {
            try solver.intersectionResult(curve:.bSpline(invalid),surface:.procedural(.originalCoons(surface)),tolerance:tolerance)
        }
    }

}
