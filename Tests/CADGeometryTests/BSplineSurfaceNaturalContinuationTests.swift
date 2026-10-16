import CADCore
import Synchronization
import Testing
import CADGeometry

@Suite("Natural B-spline continuation direct execution")
struct BSplineSurfaceNaturalContinuationTests {
    private let tolerance = ModelingTolerance.standard
    private func source() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0), Point3D(x: 1, y: 0, z: 1)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 0.5, y: 1, z: 0), Point3D(x: 1, y: 1, z: 1)]],
            weights: [[2, 2, 2], [2, 2, 2]])
    }
    private func expected(_ u: Double, _ v: Double) -> Point3D {
        Point3D(x: u, y: v, z: u <= 0.5 ? 0 : 2 * u - 1)
    }
    private func execution(_ budget: OriginalQueryBudget, sourceDepth: Int = 16) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget, limits: try .init(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, remainingSourceDepth: sourceDepth))
    }
    private func isResource(_ error: any Error, _ resource: ExactResource) -> Bool {
        guard let scalar = geometryTestOriginalFailure(error) as? ExactScalarFailure,
            case .resourceLimit(let actual) = scalar else { return false }
        return actual == resource
    }
    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let cancelAt: Int?
        init(cancelAt: Int? = nil) { self.cancelAt = cancelAt }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let ordinal = state.withLock { value in value += 1; return value }
            if ordinal == cancelAt { throw .cancelled }
        }
    }
    private func retained(using execution: inout OriginalQueryExecution) throws -> BSplineSurfaceNaturalContinuation {
        var input = source()
        let result = try BSplineSurfaceNaturalContinuation(input, tolerance: tolerance, using: &execution)
        input.controlPoints[0][0].z = 99
        input.weights[1][2] = 7
        #expect(input != source())
        return result
    }

    @Test func independentLawAndRetainedCOWSource() throws {
        var direct = try execution(OriginalQueryBudget())
        let continuation = try retained(using: &direct)
        let ordinary = try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance)
        for u in [-0.5, 0, 0.5, 1, 1.5] {
            for v in [-0.5, 0, 0.5, 1, 1.5] {
                let value = try continuation.point(u: u, v: v, using: &direct)
                let ordinaryValue = try ordinary.point(u: u, v: v)
                #expect(value == expected(u, v))
                #expect(ordinaryValue == value)
            }
        }
        #expect(direct.sourceDepth == 0)
    }

    @Test func coldPreparationAndReadUseMeasuredCumulativeLimits() throws {
        let measured = try OriginalQueryBudget()
        var measuring = try execution(measured)
        let continuation = try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance, using: &measuring)
        let prepared = measured.snapshot
        let point = try continuation.point(u: 1.5, v: -0.5, using: &measuring)
        #expect(point == expected(1.5, -0.5))
        let complete = measured.snapshot
        #expect(prepared.work > 0 && prepared.storageBytes > 0)
        #expect(complete.work > prepared.work && complete.storageBytes > prepared.storageBytes)
        let exactBudget = try OriginalQueryBudget(workLimit: complete.work, storageByteLimit: complete.storageBytes)
        var exact = try execution(exactBudget)
        let exactOwner = try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance, using: &exact)
        let exactPoint = try exactOwner.point(u: 1.5, v: -0.5, using: &exact)
        #expect(exactPoint == point)
        #expect(exactBudget.snapshot.work == complete.work)
        #expect(exactBudget.snapshot.storageBytes == complete.storageBytes)
        for resource in [ExactResource.work, .storage] {
            let preparationBudget = try OriginalQueryBudget(
                workLimit: resource == .work ? prepared.work - 1 : nil,
                storageByteLimit: resource == .storage ? prepared.storageBytes - 1 : nil)
            var preparationRead = try execution(preparationBudget)
            geometryTestExpectFailure({ isResource($0, resource) }) {
                try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance, using: &preparationRead)
            }
            let readBudget = try OriginalQueryBudget(
                workLimit: resource == .work ? complete.work - 1 : nil,
                storageByteLimit: resource == .storage ? complete.storageBytes - 1 : nil)
            var read = try execution(readBudget)
            let owner = try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance, using: &read)
            #expect(readBudget.snapshot.work == prepared.work)
            #expect(readBudget.snapshot.storageBytes == prepared.storageBytes)
            geometryTestExpectFailure({ isResource($0, resource) }) {
                try owner.point(u: 1.5, v: -0.5, using: &read)
            }
        }
        let cumulative = try OriginalQueryBudget(workLimit: complete.work)
        var first = try execution(cumulative)
        let owner = try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance, using: &first)
        _ = try owner.point(u: 1.5, v: -0.5, using: &first)
        geometryTestExpectFailure({ isResource($0, .work) }) { try owner.point(u: 1.5, v: -0.5) }
        #expect(cumulative.snapshot.work == complete.work)
        let beforeForeign = cumulative.snapshot
        let foreignBudget = try OriginalQueryBudget()
        var foreign = try execution(foreignBudget)
        let foreignPoint = try owner.point(u: 1.5, v: -0.5, using: &foreign)
        #expect(foreignPoint == point)
        #expect(foreignBudget.snapshot.work > 0 && foreignBudget.snapshot.storageBytes > 0)
        #expect(cumulative.snapshot.work == beforeForeign.work)
        #expect(cumulative.snapshot.storageBytes == beforeForeign.storageBytes)
    }

    @Test func entryAndTerminalCancellationPublishNoPoint() throws {
        let checkpoints = Checkpoints()
        let measured = try OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() })
        var measuring = try execution(measured)
        let owner = try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance, using: &measuring)
        let preparationCheckpoint = checkpoints.count
        let prepared = measured.snapshot
        _ = try owner.point(u: 1.5, v: -0.5, using: &measuring)
        let finalCheckpoint = checkpoints.count
        let complete = measured.snapshot
        for stop in [1, preparationCheckpoint, finalCheckpoint] {
            let cancellation = Checkpoints(cancelAt: stop)
            let budget = try OriginalQueryBudget(checkpoint: { try cancellation.checkpoint() })
            var read = try execution(budget)
            geometryTestExpectFailure(geometryTestIsCancelled) {
                let retained = try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance, using: &read)
                return try retained.point(u: 1.5, v: -0.5, using: &read)
            }
            let expectedWork = stop == 1 ? 0 : (stop == preparationCheckpoint ? prepared.work : complete.work)
            let expectedBytes = stop == 1 ? 0 : (stop == preparationCheckpoint ? prepared.storageBytes : complete.storageBytes)
            #expect(budget.snapshot.work == expectedWork)
            #expect(budget.snapshot.storageBytes == expectedBytes)
        }
        let cancellation = Checkpoints(cancelAt: 1)
        let foreignBudget = try OriginalQueryBudget(checkpoint: { try cancellation.checkpoint() })
        var foreign = try execution(foreignBudget)
        geometryTestExpectFailure(geometryTestIsCancelled) { try owner.point(u: 0.5, v: 0.5, using: &foreign) }
        #expect(foreignBudget.snapshot.work == 0 && foreignBudget.snapshot.storageBytes == 0)
    }

    @Test func mappedDepthRefusalPrecedesRetainedContributionCharges() throws {
        let budget = try OriginalQueryBudget()
        var preparing = try execution(budget)
        let contribution = try preparing.makeContributionHandle()
        let owner = try preparing.withContributionScope(contribution) { execution in
            try BSplineSurfaceNaturalContinuation(source(), tolerance: tolerance, using: &execution)
        }
        #expect(preparing.activeContributionCount == 0)
        var reader = try execution(budget, sourceDepth: 0)
        #expect(reader.activeContributionCount == 0)
        let before = budget.snapshot
        geometryTestExpectFailure({ error in
            guard let failure = geometryTestQueryFailure(error) else { return false }
            return failure.context.resource?.axis == .sourceDepth
                && failure.kernelFailure.code == .resourceLimitExceeded
        }) {
            try reader.withSourceDepthOffset(1) { execution in
                try owner.point(u: 0.5, v: 0.5, using: &execution)
            }
        }
        #expect(budget.snapshot.work == before.work)
        #expect(budget.snapshot.storageBytes == before.storageBytes)
        #expect(reader.activeContributionCount == 0)
    }
}
