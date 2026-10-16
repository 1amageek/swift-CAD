import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Bounded original surface-pair admission witness")
struct BoundedSurfaceSurfaceAdmissionWitnessTests {
    private enum Refusal: Error, Equatable { case work, storage }
    private let tolerance = ModelingTolerance.standard

    private func planeSource(z: Double) -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [-1, -1, 1, 1], vKnots: [-1, -1, 1, 1],
            controlPoints: [[.init(x: -1, y: -1, z: z), .init(x: 1, y: -1, z: z)],
                [.init(x: -1, y: 1, z: z), .init(x: 1, y: 1, z: z)]])
    }

    private func plane(z: Double) -> Surface3D { .bSpline(planeSource(z: z)) }

    private func query(_ producer: any BoundedSurfaceSurfaceIntersecting,
        sourceDepth: Int = 1, spatialDepth: Int = 0, algebraDepth: Int? = 32,
        work: @escaping @Sendable () throws -> Void,
        storage: (@Sendable (Int) throws -> Void)? = nil) throws -> [SurfaceSurfaceIntersection]? {
        try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: spatialDepth,
            remainingSourceDepth: sourceDepth,
            maximumAlgebraicDepth: algebraDepth ?? 32,
            consumeWorkUnits: { units in for _ in 0..<units { try work() } },
            consumeStorageBytes: storage) { queryExecution in
            try producer.intersections(first: plane(z: 0),
            second: plane(z: 1),
            boundaryPoints: [],
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func concreteAndExistentialRetainNativeExclusionAndNilStorage() throws {
        let concrete = DefaultBoundedSurfaceSurfaceIntersector()
        let counter = Mutex(0)
        let existential: any BoundedSurfaceSurfaceIntersecting = concrete
        let throughWitnessCandidate: [SurfaceSurfaceIntersection]? = try query(existential,
            work: { counter.withLock { $0 += 1 } })
        let throughWitness = try #require(throughWitnessCandidate)
        let directCandidate: [SurfaceSurfaceIntersection]? = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: nil) { queryExecution in
            try concrete.intersections(first: plane(z: 0),
            second: plane(z: 1),
            boundaryPoints: [],
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
        let direct = try #require(directCandidate)
        #expect(throughWitness.isEmpty)
        #expect(direct == throughWitness)
        #expect(counter.withLock { $0 } > 0)
        let compatibilityCandidate: [SurfaceSurfaceIntersection]? = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: nil) { queryExecution in
            try existential.intersections(first: plane(z: 0),
            second: plane(z: 1),
            boundaryPoints: [],
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
        let compatibility = try #require(compatibilityCandidate)
        #expect(compatibility == throughWitness)
    }

    @Test(.timeLimit(.minutes(1)))
    func existentialPublishesTheRetainedOriginalNativeTuple() throws {
        let x = [-1.0, 0, 1], square = [1.0, -1, 1]
        let bowl = BSplineSurface3D(uDegree: 2, vDegree: 2,
            uKnots: [-1, -1, -1, 1, 1, 1], vKnots: [-1, -1, -1, 1, 1, 1],
            controlPoints: (0..<3).map { v in (0..<3).map { u in
                Point3D(x: x[u], y: x[v], z: square[u] + square[v]) } })
        let producer: any BoundedSurfaceSurfaceIntersecting = DefaultBoundedSurfaceSurfaceIntersector()
        let candidate: [SurfaceSurfaceIntersection]? = try geometryTestWithQuery(maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: nil) { queryExecution in
            try producer.intersections(first: plane(z: 0),
            second: .bSpline(bowl),
            boundaryPoints: [],
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
        let result = try #require(candidate)
        #expect(result.count == 1)
        guard case .point(let point) = try #require(result.first) else {
            Issue.record("The original tangent tuple became another intersection stratum.")
            return
        }
        let original = try #require(point.originalNativePoint)
        #expect(original.owner.firstSurface == planeSource(z: 0))
        #expect(original.owner.secondSurface == bowl)
        #expect(original.owner.owns(original))
        #expect(point.point == .origin)
        #expect(point.firstSurfaceParameter.u == 0 && point.firstSurfaceParameter.v == 0)
        #expect(point.secondSurfaceParameter.u == 0 && point.secondSurfaceParameter.v == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func callbacksPropagateIndependentRefusals() throws {
        let producer: any BoundedSurfaceSurfaceIntersecting = DefaultBoundedSurfaceSurfaceIntersector()
        geometryTestExpectFailure({ if case .work? = geometryTestOriginalFailure($0) as? Refusal { true } else { false } }) { try query(producer, work: { throw Refusal.work }) }
        geometryTestExpectFailure({ if case .storage? = geometryTestOriginalFailure($0) as? Refusal { true } else { false } }) {
            try query(producer, work: {}, storage: { _ in throw Refusal.storage })
        }
        let bytes = Mutex(0)
        let candidate: [SurfaceSurfaceIntersection]? = try query(producer,
            work: {}, storage: { count in bytes.withLock { $0 += count } })
        let result = try #require(candidate)
        #expect(result.isEmpty)
        #expect(bytes.withLock { $0 } > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceSpatialAndAlgebraCapabilitiesStayIndependent() throws {
        let producer: any BoundedSurfaceSurfaceIntersecting = DefaultBoundedSurfaceSurfaceIntersector()
        let candidate: [SurfaceSurfaceIntersection]? = try query(producer,
            spatialDepth: 0, algebraDepth: 32, work: {})
        let result = try #require(candidate)
        #expect(result.isEmpty)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { try query(producer, sourceDepth: 0, work: {}) }
        #expect(throws: GeometryConversionError.self) { try query(producer, algebraDepth: 33, work: {}) }
        #expect(throws: GeometryConversionError.self) { try query(producer, spatialDepth: -1, work: {}) }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationCannotPublishNativeSuccess() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try query(DefaultBoundedSurfaceSurfaceIntersector(), work: {})
        }
        do { _ = try await task.value; Issue.record("Cancelled bounded producer published success.") }
        catch where geometryTestIsCancelled(error) {}
    }

    private struct LegacyOnly: BoundedSurfaceSurfaceIntersecting {
        func intersections(first: Surface3D, second: Surface3D, boundaryPoints: [Point3D],
            options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> [SurfaceSurfaceIntersection]? { [] }
    }

    @Test(.timeLimit(.minutes(1)))
    func legacyConformerCannotPublishSelectedAdmission() throws {
        do {
            _ = try query(LegacyOnly(), work: {})
            Issue.record("A legacy producer supplied an independent algebra witness.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .unsupportedCapability) }
    }
}
