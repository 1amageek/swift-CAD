import CADCore
import Synchronization
import Testing
@testable import CADGeometry

@Suite("Original whole-plane offset relation", .timeLimit(.minutes(1)))
struct OffsetPlaneOriginalRelationTests {
    private func execution(_ budget: OriginalQueryBudget, sourceDepth: Int = 16) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 0, maximumCoefficientDepth: 0,
            remainingSourceDepth: sourceDepth, maximumTransportDepth: 0,
            maximumSubdivisionDepth: 0, maximumSpans: 1))
    }

    private func relation(_ source: Plane3D, target: Plane3D, distance: Double,
        using query: inout OriginalQueryExecution) throws -> Bool {
        try OriginalPlaneOffsetRelation.proves(source: source, target: target,
            distance: distance, tolerance: .standard, using: &query)
    }

    @Test
    func wholePlaneIdentityAcceptsSignedNonunitObliqueAndAuthoredCharts() throws {
        let oblique = Plane3D(origin: .init(x: 1, y: -2, z: 4), normal: .init(x: 3, y: 4, z: 0))
        for sign in [-1.0, 1.0] {
            var query = try execution(OriginalQueryBudget())
            let target = Plane3D(origin: .init(x: 1 + sign * 3, y: -2 + sign * 4, z: 4), normal: oblique.normal)
            #expect(try relation(oblique, target: target, distance: sign * 5, using: &query))
            let offset = OffsetSurface3D(source: .plane(oblique), distance: sign * 5)
            #expect(try offset.exactChartPreservingSurface(tolerance: .standard, using: &query) == .plane(target))
        }
        for normal in [Vector3D.unitZ, -Vector3D.unitZ] {
            // U is non-axis and retained literally; its exact length need not be one.
            let source = Plane3D(origin: .origin, normal: normal, uDirection: .init(x: 0.6, y: 0.8, z: 0))
            let target = Plane3D(origin: .init(x: 0, y: 0, z: normal.z * 0.125),
                normal: normal, uDirection: source.uDirection)
            var query = try execution(OriginalQueryBudget())
            #expect(try relation(source, target: target, distance: 0.125, using: &query))
            #expect(try relation(source, target: source, distance: 0, using: &query))
        }
    }

    @Test
    func wrongSideLengthBasisAndNearNormalDoNotBecomeOriginalEquality() throws {
        let source = Plane3D(origin: .origin, normal: .init(x: 3, y: 4, z: 0))
        let wrong = [
            Plane3D(origin: .init(x: -3, y: -4, z: 0), normal: source.normal),
            Plane3D(origin: .init(x: 6, y: 8, z: 0), normal: source.normal),
            Plane3D(origin: .init(x: 3, y: 4, z: 1e-12), normal: source.normal),
            Plane3D(origin: .init(x: 3, y: 4, z: 0), normal: -source.normal)
        ]
        var query = try execution(OriginalQueryBudget())
        for target in wrong { #expect(try !relation(source, target: target, distance: 5, using: &query)) }
        #expect(try !relation(source, target: wrong[0], distance: 0, using: &query))
        let framed = Plane3D(origin: .origin, normal: .unitZ, uDirection: .unitX)
        let changed = Plane3D(origin: .init(x: 0, y: 0, z: 1), normal: .unitZ, uDirection: .unitY)
        #expect(try !relation(framed, target: changed, distance: 1, using: &query))
        let erased = Plane3D(origin: changed.origin, normal: .unitZ)
        #expect(try !relation(framed, target: erased, distance: 1, using: &query))
    }

    private func assertRetained(_ source: Plane3D, distance: Double,
        using query: inout OriginalQueryExecution) throws {
        let offset = OffsetSurface3D(source: .plane(source), distance: distance)
        #expect(try offset.exactChartPreservingSurface(tolerance: .standard, using: &query) == nil)
        let image = try offset.parameterCurveImage(transporting: .constantV(v: 0, uStart: 0, uEnd: 1),
            tolerance: .standard, using: &query)
        let target = try image.targetSurface(tolerance: .standard, using: &query)
        #expect(target == .procedural(.offset(offset)))
        try image.validateOriginalRelation(on: target, tolerance: .standard,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 0, using: &query)
        let chart = SurfaceParameterCurve.offsetSurfaceImage(image)
        let bound = try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(
            curve: .surfaceLift(.init(surface: target, parameterCurve: chart)), from: 0, to: 1,
            surface: target, parameterCurve: chart, options: .init(maximumSubdivisionDepth: 1,
                maximumCellCount: 1, maximumDeviation: ModelingTolerance.standard.distance),
            tolerance: .standard, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
            remainingSourceDepth: 16, maximumAlgebraicDepth: 0, using: &query)
        #expect(bound == 0)
    }

    @Test
    func roundedOrUnavailablePlaneCandidatesRetainTheOriginalOffset() throws {
        var query = try execution(OriginalQueryBudget(workLimit: 262_144))
        try assertRetained(.init(origin: .init(x: 0, y: 0, z: 9_007_199_254_740_992), normal: .unitZ),
            distance: 1, using: &query)
        try assertRetained(.init(origin: .origin, normal: .init(x: 1, y: 1, z: 0)),
            distance: 1, using: &query)
        // Validation admits this near-orthogonal frame, but its derivative cross is not N.
        try assertRetained(.init(origin: .origin, normal: .unitZ,
            uDirection: .init(x: 1, y: 0, z: ModelingTolerance.standard.angle / 2)),
            distance: 0.125, using: &query)
        try assertRetained(.init(origin: .origin, normal: .init(x: 0, y: 0, z: 1e-200)),
            distance: 1, using: &query)
        #expect(query.valueDepth == 0 && query.coefficientDepth == 0)
    }

    private func acceptedImage(using query: inout OriginalQueryExecution) throws {
        let source = Surface3D.plane(.init(origin: .origin, normal: .unitZ))
        let image = try OffsetSurface3D(source: source, distance: 0.005)
            .parameterCurveImage(transporting: .constantV(v: 0, uStart: -0.020, uEnd: 0.020),
                tolerance: .standard, using: &query)
        let target = try image.targetSurface(tolerance: .standard, using: &query)
        #expect(target == .plane(.init(origin: .init(x: 0, y: 0, z: 0.005), normal: .unitZ)))
        try image.validateOriginalRelation(on: target, tolerance: .standard,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 0, using: &query)
    }

    private func resource(_ error: any Error, _ expected: ExactResource) -> Bool {
        guard let failure = geometryTestOriginalFailure(error) as? ExactScalarFailure,
            case .resourceLimit(let actual) = failure else { return false }
        return actual == expected
    }

    @Test
    func materializerAndReceiverShareExactCallerWorkBytesAndRationalDepth() throws {
        var measuring = try execution(OriginalQueryBudget())
        try acceptedImage(using: &measuring)
        let measured = measuring.budget.snapshot
        #expect(measured.work > 0 && measured.storageBytes > 0)
        var exact = try execution(OriginalQueryBudget(workLimit: measured.work, storageByteLimit: measured.storageBytes))
        try acceptedImage(using: &exact)
        #expect(exact.budget.snapshot.work == measured.work && exact.budget.snapshot.storageBytes == measured.storageBytes)
        #expect(exact.valueDepth == 0 && exact.coefficientDepth == 0)
        var workShort = try execution(OriginalQueryBudget(workLimit: measured.work - 1))
        geometryTestExpectFailure({ resource($0, .work) }) { try acceptedImage(using: &workShort) }
        var bytesShort = try execution(OriginalQueryBudget(storageByteLimit: measured.storageBytes - 1))
        geometryTestExpectFailure({ resource($0, .storage) }) { try acceptedImage(using: &bytesShort) }
        var noBytes = try execution(OriginalQueryBudget(storageByteLimit: 0))
        geometryTestExpectFailure({ resource($0, .storage) }) { try acceptedImage(using: &noBytes) }
    }

    @Test
    func receiverRetainsSourceDomainAndInvalidSourceRefusals() throws {
        var query = try execution(OriginalQueryBudget())
        let offset = OffsetSurface3D(source: .plane(.init(origin: .origin, normal: .unitZ)), distance: 0.125)
        let image = try offset.parameterCurveImage(transporting: .constantV(v: 0, uStart: 0, uEnd: 1),
            tolerance: .standard, using: &query)
        geometryTestExpectFailure({ geometryTestKernelFailure($0)?.code == .unsupportedCapability }) {
            try image.validateOriginalRelation(on: .plane(.init(origin: .init(x: 0, y: 0, z: -0.125), normal: .unitZ)),
                tolerance: .standard, remainingSourceDepth: 16, maximumSubdivisionDepth: 0, using: &query)
        }
        #expect(throws: GeometryConversionError.self) {
            try image.validateOriginalRelation(on: .procedural(.offset(offset)), tolerance: .standard,
                remainingSourceDepth: 0, maximumSubdivisionDepth: 0, using: &query)
        }
        #expect(throws: GeometryError.self) {
            try relation(.init(origin: .origin, normal: .zero), target: .init(origin: .origin, normal: .zero),
                distance: 0, using: &query)
        }
        #expect(throws: GeometryError.self) {
            try OffsetSurface3D(source: offset.source, distance: .infinity)
                .exactChartPreservingSurface(tolerance: .standard, using: &query)
        }
    }

    private final class Checkpoints: Sendable {
        private let countState = Mutex(0)
        private let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { countState.withLock { $0 } }
        func check() throws(ExactScalarFailure) {
            let ordinal = countState.withLock { $0 += 1; return $0 }
            if ordinal == stop { throw .cancelled }
        }
    }

    @Test
    func entryAndTerminalCancellationDoNotPublishAnImageRelation() throws {
        let visits = Checkpoints()
        var measuring = try execution(OriginalQueryBudget(checkpoint: { try visits.check() }))
        try acceptedImage(using: &measuring)
        let measured = measuring.budget.snapshot
        for stop in [1, visits.count] {
            let stopped = Checkpoints(stop: stop)
            var query = try execution(OriginalQueryBudget(checkpoint: { try stopped.check() }))
            geometryTestExpectFailure(geometryTestIsCancelled) { try acceptedImage(using: &query) }
            #expect(query.budget.snapshot.work == (stop == 1 ? 0 : measured.work))
            #expect(query.budget.snapshot.storageBytes == (stop == 1 ? 0 : measured.storageBytes))
        }
    }
}
