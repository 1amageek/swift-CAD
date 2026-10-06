import CADCore
import CADGeometry
import Foundation
import Synchronization
import Testing

@Suite("Public original native surface-surface isolated points", .serialized)
struct NativeSurfaceSurfacePointTests {
    private let tolerance = ModelingTolerance.standard

    private func plane(z: Double = 0, folded: Bool = false, weighted: Bool = false) -> BSplineSurface3D {
        if folded {
            return .init(uDegree: 2, vDegree: 1, uKnots: [-1,-1,-1,1,1,1], vKnots: [-1,-1,1,1],
                controlPoints: [
                    [.init(x: 1,y: -1,z: z), .init(x: -1,y: -1,z: z), .init(x: 1,y: -1,z: z)],
                    [.init(x: 1,y: 1,z: z), .init(x: -1,y: 1,z: z), .init(x: 1,y: 1,z: z)]])
        }
        return .init(uDegree: 1, vDegree: 1, uKnots: [-1,-1,1,1], vKnots: [-1,-1,1,1],
            controlPoints: [[.init(x: -1,y: -1,z: z), .init(x: 1,y: -1,z: z)],
                [.init(x: -1,y: 1,z: z), .init(x: 1,y: 1,z: z)]],
            weights: weighted ? [[1,2],[2,4]] : [[1,1],[1,1]])
    }

    /// Original graph z = u^2 + v^2, with x offset plus u and y = v.
    private func bowl(offset: Double = 0, weight: Double = 1) -> BSplineSurface3D {
        let x = [-1.0,0,1], square = [1.0,-1,1]
        let factors = [1.0, weight, 1.0]
        return .init(uDegree: 2, vDegree: 2, uKnots: [-1,-1,-1,1,1,1], vKnots: [-1,-1,-1,1,1,1],
            controlPoints: (0..<3).map { v in (0..<3).map { u in
                .init(x: offset + x[u] / factors[u], y: x[v] / factors[v],
                    z: (square[u] + square[v]) / (factors[u] * factors[v])) } },
            weights: (0..<3).map { v in (0..<3).map { u in factors[u] * factors[v] } })
    }

    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in }, retainStorage: { _ in },
            visitCell: { _ in }, visitCoefficientCell: { _ in })
    }

    private func points(_ result: SurfaceSurfaceIntersectionResult) throws -> [SurfaceSurfaceIntersectionPoint] {
        try result.intersections.map {
            guard case .point(let point) = $0 else {
                throw GeometryConversionError.invalidInput("Expected complete isolated native points.")
            }
            return point
        }
    }

    private func finiteResult(first: Surface3D, second: Surface3D,
        tolerance: ModelingTolerance) throws -> SurfaceSurfaceIntersectionResult {
        let work = Mutex(80_000_000), bytes = Mutex(1_073_741_824)
        let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: first, second: second,
            tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { try work.withLock { remaining in
                guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Finite SSI caller work exhausted.") }
                remaining -= 1
            } }, consumeStorage: { count in try bytes.withLock { remaining in
                guard count <= remaining else { throw GeometryConversionError.resourceLimitExceeded("Finite SSI caller storage exhausted.") }
                remaining -= count
            } }, maximumAlgebraicDepth: 32)
        print("Finite SSI work=\(80_000_000 - work.withLock { $0 }) bytes=\(1_073_741_824 - bytes.withLock { $0 })")
        return result
    }

    @Test(.timeLimit(.minutes(2)))
    func heavyOriginalProductsRespectDefaultAndFiniteCaller() throws {
        let epsilon = 1.0 / 1_048_576.0
        let cases: [(Surface3D,Surface3D,ModelingTolerance,Int)] = [
            (.bSpline(plane()), .bSpline(bowl(weight: 2)), tolerance, 1),
            (.bSpline(plane(weighted: true)), .bSpline(bowl()), tolerance, 1),
            (.bSpline(plane(folded: true)), .bSpline(bowl(offset: epsilon * epsilon)),
                .init(distance: 1e-4, angle: 1e-9), 2)]
        for (caseIndex, input) in cases.enumerated() {
            let (first,second,tolerance,count) = input
            var ordinary: SurfaceSurfaceIntersectionResult?
            do {
                ordinary = try DefaultSurfaceSurfaceIntersector().intersectionResult(
                    first: first, second: second, tolerance: tolerance)
            } catch let error as KernelError {
                guard error.code == .resourceLimitExceeded else { throw error }
            }
            let result = try finiteResult(first: first, second: second, tolerance: tolerance)
            var publications = [result]
            if let ordinary {
                #expect(ordinary.intersections == result.intersections)
                publications.append(ordinary)
            }
            for publication in publications {
                let published = try points(publication)
                let receipt = try #require(publication.originalNativePoints)
                #expect(published.count == count && receipt.count == count)
                #expect(receipt.nativeDomains.count == 4 && receipt.effectiveDomains?.count == 4)
                var admission = usage()
                for ordinal in 0..<count {
                    let handle = try receipt.point(at: ordinal)
                    #expect(receipt.owns(try #require(published[ordinal].originalNativePoint)))
                    for axis in 0..<4 {
                        let station: ExactRationalCoefficient
                        if caseIndex == 1 && axis < 2 {
                            station = try ExactRationalCoefficient.one.negated.divided(
                                by: .originalDouble(3, usage: &admission), usage: &admission)
                        } else if caseIndex == 2 && axis == 0 {
                            station = try .originalDouble(ordinal == 0 ? -epsilon : epsilon, usage: &admission)
                        } else { station = .zero }
                        #expect(try handle.compareParameter(axis: axis, to: station, in: receipt,
                            maximumAlgebraicDepth: 32, usage: &admission) == .zero)
                    }
                }
                if count == 2 {
                    #expect(published[0].firstSurfaceParameter.u < published[1].firstSurfaceParameter.u)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func isolatedRankDeficientContactAndRoutes() throws {
        let first = Surface3D.bSpline(plane()), second = Surface3D.bSpline(bowl())
        let solver = DefaultSurfaceSurfaceIntersector()
        let result = try solver.intersectionResult(first: first, second: second, tolerance: tolerance)
        let published = try points(result), receipt = try #require(result.originalNativePoints)
        #expect(published.count == 1 && receipt.count == 1)
        #expect(published[0].point == Point3D(x: 0,y: 0,z: 0))
        #expect(receipt.firstSurface == plane() && receipt.secondSurface == bowl())
        #expect(receipt.nativeDomains.count == 4 && receipt.effectiveDomains?.count == 4)
        #expect(receipt.owns(try #require(published[0].originalNativePoint)))
        #expect(try solver.intersections(first: first, second: second, tolerance: tolerance) == result.intersections)
        let work = Mutex(0), bytes = Mutex(0)
        let selected = try solver.intersectionResult(first: first, second: second,
            options: .init(), tolerance: tolerance, maximumSpanCount: 1,
            maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { work.withLock { $0 += 1 } },
            consumeStorage: { value in bytes.withLock { $0 += value } }, maximumAlgebraicDepth: 32)
        #expect(selected.intersections == result.intersections)
        #expect(work.withLock { $0 } > 0 && bytes.withLock { $0 } > 0)
        let box = SurfaceParameterBox(u: try .init(lower: -0.5,upper: 0.5), v: try .init(lower: -0.5,upper: 0.5))
        let domain = try solver.intersectionResult(first: first, over: box, second: second, over: box,
            options: .init(), tolerance: tolerance, maximumSpanCount: 1,
            maximumSubdivisionDepth: 0, remainingSourceDepth: 1, consumeWork: {}, consumeStorage: { _ in },
            maximumAlgebraicDepth: 32)
        #expect(domain.intersections == result.intersections)
        let session = try solver.prepareOriginalPair(first: first, second: second,
            tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1, consumeWork: {}, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
        let retained = try session.intersectionResult(firstBox: box, secondBox: box, options: .init())
        #expect(retained.intersections == result.intersections && retained.originalNativePoints?.count == 1)
        #expect(try session.intersections(firstBox: box, secondBox: box, options: .init()) == result.intersections)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonClampedSingleSpanUsesOriginalProtocolWitnessInBothOrders() throws {
        var source = plane()
        source.uKnots = [-2,-1,1,2]
        source.vKnots = [-2,-1,1,2]
        let target = bowl()
        let solver: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        for reverse in [false,true] {
            let first = reverse ? target : source, second = reverse ? source : target
            let result = try solver.intersectionResult(first: .bSpline(first), second: .bSpline(second),
                options: .init(), tolerance: tolerance)
            let receipt = try #require(result.originalNativePoints)
            let published = try points(result)
            #expect(published.count == 1 && receipt.count == 1)
            #expect(receipt.firstSurface == first && receipt.secondSurface == second)
            #expect(published[0].point == Point3D(x: 0,y: 0,z: 0))
            #expect(published[0].firstSurfaceParameter.u == 0 && published[0].firstSurfaceParameter.v == 0)
            #expect(published[0].secondSurfaceParameter.u == 0 && published[0].secondSurfaceParameter.v == 0)
            let handle = try receipt.point(at: 0)
            #expect(receipt.owns(try #require(published[0].originalNativePoint)))
            var admission = usage()
            let lower = try ExactRationalCoefficient.originalDouble(-1, usage: &admission)
            let upper = ExactRationalCoefficient.one
            #expect(receipt.nativeDomains.count == 4 && receipt.effectiveDomains?.count == 4)
            for axis in 0..<4 {
                #expect(receipt.nativeDomains[axis].lower == lower && receipt.nativeDomains[axis].upper == upper)
                #expect(try handle.compareParameter(axis: axis, to: .zero, in: receipt,
                    maximumAlgebraicDepth: 32, usage: &admission) == .zero)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func weightedBilinearClosedBoundaryContact() throws {
        let first = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1], controlPoints: [
                [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]], weights: [[1,2],[2,4]])
        let second = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1], controlPoints: [
                [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 1)],
                [.init(x: 0,y: 1,z: 1), .init(x: 1,y: 1,z: 2)]])
        let normal = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: .bSpline(first),
            second: .bSpline(second), tolerance: tolerance)
        let selected = try finiteResult(first: .bSpline(first), second: .bSpline(second), tolerance: tolerance)
        #expect(normal.intersections == selected.intersections && normal.intersections.count == 1)
        let point = try #require(points(normal).first), receipt = try #require(normal.originalNativePoints)
        #expect(point.point == Point3D(x: 0,y: 0,z: 0))
        #expect(receipt.firstSurface == first && receipt.secondSurface == second)
        var admission = usage()
        let handle = try receipt.point(at: 0)
        for axis in 0..<4 {
            #expect(try handle.compareParameter(axis: axis, to: .zero, in: receipt,
                maximumAlgebraicDepth: 32, usage: &admission) == .zero)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func distinctPreimagesSameXYZAndExactOrdering() throws {
        let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(
            first: .bSpline(plane(folded: true)), second: .bSpline(bowl(offset: 0.25)), tolerance: tolerance)
        let published = try points(result), receipt = try #require(result.originalNativePoints)
        #expect(published.count == 2 && receipt.count == 2)
        #expect(published[0].point == published[1].point)
        #expect(published[0].firstSurfaceParameter.u == -0.5 && published[1].firstSurfaceParameter.u == 0.5)
        #expect(throws: KernelError.self) {
            try DefaultSurfaceSurfaceIntersector().intersectionResult(first: .bSpline(plane(folded: true)),
                second: .bSpline(bowl(offset: 0.25)), options: .init(maximumSeedCount: 1), tolerance: tolerance)
        }
        var admission = usage()
        for ordinal in 0..<2 {
            let handle = try receipt.point(at: ordinal)
            let station = try ExactRationalCoefficient.originalDouble(ordinal == 0 ? -0.5 : 0.5, usage: &admission)
            #expect(try handle.compareParameter(axis: 0, to: station, in: receipt,
                maximumAlgebraicDepth: 32, usage: &admission) == .zero)
            for axis in 1..<4 {
                #expect(try handle.compareParameter(axis: axis, to: .zero, in: receipt,
                    maximumAlgebraicDepth: 32, usage: &admission) == .zero)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func retainedIrrationalCoordinateAndForeignIdentity() throws {
        let solver = DefaultSurfaceSurfaceIntersector()
        let retained = try finiteResult(first: .bSpline(plane(folded: true)),
            second: .bSpline(bowl(offset: 0.5)), tolerance: tolerance)
        let receipt = try #require(retained.originalNativePoints)
        let handle = try receipt.point(at: 1)
        let coordinate = try handle.parameter(axis: 0, in: receipt)
        let interval = try coordinate.enclosed(maximumDepth: 32, maximumCoefficientDepth: 32, usage: usage())
        var admission = usage()
        let limit = try ExactRationalCoefficient.originalDouble(tolerance.distance, usage: &admission)
        #expect(try !interval.upper.subtracting(interval.lower, usage: &admission).subtracting(limit, usage: &admission).isPositive)
        #expect(try handle.compareParameter(axis: 0, to: .zero, in: receipt,
            maximumAlgebraicDepth: 32, usage: &admission) == .positive)
        let foreign = try #require(solver.intersectionResult(first: .bSpline(plane()),
            second: .bSpline(bowl()), tolerance: tolerance).originalNativePoints)
        #expect(!foreign.owns(handle))
        #expect(throws: GeometryConversionError.self) { try handle.parameter(axis: 0, in: foreign) }
    }

    @Test(.timeLimit(.minutes(1)))
    func emptyCoverageBoundarySingletonAndPositiveDimension() throws {
        let solver = DefaultSurfaceSurfaceIntersector()
        let empty = try solver.intersectionResult(first: .bSpline(plane(z: -1)),
            second: .bSpline(bowl()), tolerance: tolerance)
        #expect(empty.intersections.isEmpty && empty.originalNativePoints?.count == 0)
        #expect(empty.originalNativePoints?.effectiveDomains?.count == 4)
        let singleton = SurfaceParameterBox(u: try .init(lower: 0,upper: 0), v: try .init(lower: 0,upper: 0))
        let point = try solver.intersectionResult(first: .bSpline(plane()), over: singleton,
            second: .bSpline(bowl()), over: singleton, options: .init(), tolerance: tolerance,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: {}, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
        #expect(point.intersections.count == 1 && point.originalNativePoints?.count == 1)
        let excluded = SurfaceParameterBox(u: try .init(lower: 2,upper: 3), v: try .init(lower: 0,upper: 1))
        let outside = try solver.intersectionResult(first: .bSpline(plane()), over: excluded,
            second: .bSpline(bowl()), over: singleton, options: .init(), tolerance: tolerance,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: {}, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
        #expect(outside.intersections.isEmpty && outside.originalNativePoints?.effectiveDomains == nil)
        do {
            _ = try solver.intersections(first: .bSpline(plane()), second: .bSpline(plane()), tolerance: tolerance)
            Issue.record("Positive-dimensional native coverage must fail in the discrete adapter.")
        } catch let error as KernelError { #expect(error.code == .nonDiscreteIntersection) }
    }

    @Test(.timeLimit(.minutes(1)))
    func independentLimitsAndOneCallerAllowance() throws {
        let solver = DefaultSurfaceSurfaceIntersector(), first = Surface3D.bSpline(plane()), second = Surface3D.bSpline(bowl())
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(first: first, second: second, options: .init(maximumSubdivisionCells: 1), tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(first: first, second: second, options: .init(), tolerance: tolerance,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 0,
                consumeWork: {}, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
        }
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(first: .bSpline(plane(folded: true)),
                second: .bSpline(bowl(offset: 0.5)), options: .init(), tolerance: tolerance,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: {}, consumeStorage: { _ in }, maximumAlgebraicDepth: 0)
        }
        let work = Mutex(0), bytes = Mutex(0)
        let full = try solver.intersectionResult(first: first, second: second, options: .init(), tolerance: tolerance,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { work.withLock { $0 += 1 } }, consumeStorage: { value in bytes.withLock { $0 += value } },
            maximumAlgebraicDepth: 32)
        #expect(full.intersections.count == 1)
        let requiredWork = work.withLock { $0 }, requiredBytes = bytes.withLock { $0 }
        for storageFailure in [false,true] {
            let remainingWork = Mutex(requiredWork - (storageFailure ? 0 : 1))
            let remainingBytes = Mutex(requiredBytes - (storageFailure ? 1 : 0))
            #expect(throws: GeometryConversionError.self) {
                try solver.intersectionResult(first: first, second: second, options: .init(), tolerance: tolerance,
                    maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                    consumeWork: { try remainingWork.withLock { value in
                        guard value > 0 else { throw GeometryConversionError.resourceLimitExceeded("Caller work exhausted.") }; value -= 1 } },
                    consumeStorage: { count in try remainingBytes.withLock { value in
                        guard count <= value else { throw GeometryConversionError.resourceLimitExceeded("Caller bytes exhausted.") }; value -= count } },
                    maximumAlgebraicDepth: 32)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationAtFinalStorageAndCodableAuthority() async throws {
        let solver = DefaultSurfaceSurfaceIntersector()
        for noRoot in [false,true] {
            let first = Surface3D.bSpline(plane(z: noRoot ? -1 : 0)), second = Surface3D.bSpline(bowl())
            let calls = Mutex(0)
            _ = try solver.intersectionResult(first: first, second: second, options: .init(), tolerance: tolerance,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: {}, consumeStorage: { _ in calls.withLock { $0 += 1 } }, maximumAlgebraicDepth: 32)
            let final = calls.withLock { $0 }, current = Mutex(0)
            let task = Task {
                try solver.intersectionResult(first: first, second: second, options: .init(), tolerance: tolerance,
                    maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                    consumeWork: {}, consumeStorage: { _ in
                        if current.withLock({ $0 += 1; return $0 }) == final {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    }, maximumAlgebraicDepth: 32)
            }
            do { _ = try await task.value; Issue.record("Final callback cancellation must propagate.") }
            catch is CancellationError {}
        }
        let result = try solver.intersectionResult(first: .bSpline(plane()), second: .bSpline(bowl()), tolerance: tolerance)
        let original = try #require(points(result).first)
        let decoded = try JSONDecoder().decode(SurfaceSurfaceIntersectionPoint.self, from: JSONEncoder().encode(original))
        #expect(decoded == original && decoded.originalNativePoint == nil)
        #expect(Set([decoded,original]).count == 1)
    }
}
