import CADCore
import Synchronization
import Testing
@testable import CADGeometry

@Suite("Original two-point polyline bounds", .timeLimit(.minutes(1)))
struct OriginalTwoPointPolylineBoundsTests {
    private func execution(_ budget: OriginalQueryBudget, algebra: Int = 32) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: algebra, maximumCoefficientDepth: algebra,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumSpans: 64))
    }

    private func enclosure(_ points: [SurfaceParameter], lower: Double = 0, upper: Double = 1,
        spans: Int = 1, algebra: Int = 0, using execution: inout OriginalQueryExecution) throws
        -> (u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet) {
        try OriginalPolylineParameterBounds.enclosure(points, over: .init(lower: lower, upper: upper),
            order: 3, tolerance: .standard, maximumSpanCount: spans,
            maximumAlgebraicDepth: algebra, using: &execution)
    }

    private func contains(_ interval: OutwardScalarInterval, _ value: Double) {
        #expect(interval.lower <= value && interval.upper >= value)
    }

    @Test(arguments: [false, true])
    func irrationalSegmentLengthCancelsBeforeOriginalFractionEvaluation(_ reversed: Bool) throws {
        let a = SurfaceParameter(u: 0.125, v: -0.25), b = SurfaceParameter(u: 1.125, v: 0.75)
        let points = reversed ? [b, a] : [a, b]
        // The original length is sqrt(2); its only normalized segment still has gain one.
        for (lower, upper) in [(0.0, 1.0), (0.25, 0.75), (0.0, 0.0), (1.0, 1.0),
            (-0.5, 0.5), (0.5, 1.5)] {
            var query = try execution(OriginalQueryBudget(workLimit: 262_144), algebra: 0)
            let jet = try enclosure(points, lower: lower, upper: upper, using: &query)
            let first = max(0, lower), last = min(1, upper), gain = reversed ? -1.0 : 1.0
            for (coordinate, origin) in [(jet.u, points[0].u), (jet.v, points[0].v)] {
                let value = try coordinate.coefficient(0, 0)
                contains(value, origin + gain * first); contains(value, origin + gain * last)
                contains(try coordinate.coefficient(1, 0), gain)
                for order in 2...3 {
                    let higher = try coordinate.coefficient(order, 0)
                    #expect(higher.lower == 0 && higher.upper == 0)
                }
            }
            #expect(query.budget.snapshot.work > 0)
        }
    }

    @Test
    func invalidOrUncoveredSourcesKeepTypedRefusal() throws {
        let points = [SurfaceParameter(u: 0, v: 0), SurfaceParameter(u: 1, v: 1)]
        var query = try execution(OriginalQueryBudget())
        for (lower, upper) in [(-2.0, -1.0), (2.0, 3.0)] {
            #expect(throws: GeometryConversionError.self) {
                try enclosure(points, lower: lower, upper: upper, using: &query)
            }
        }
        #expect(throws: GeometryConversionError.self) { try enclosure(points, spans: 0, using: &query) }
        #expect(throws: KernelError.self) { try enclosure([points[0], points[0]], using: &query) }
        #expect(throws: KernelError.self) { try enclosure(points, algebra: -1, using: &query) }
        #expect(throws: KernelError.self) {
            try enclosure([points[0], .init(u: .infinity, v: 0)], using: &query)
        }
        geometryTestExpectFailure({ geometryTestKernelFailure($0)?.code == .unsupportedCapability }) {
            try OriginalParameterCurveHigherTaylor.enclosure(.polyline(points), over: .init(lower: 0, upper: 1),
                order: 3, tolerance: .standard, maximumSpanCount: 1, maximumSubdivisionDepth: 32,
                remainingSourceDepth: 16, maximumAlgebraicDepth: nil, using: &query)
        }
        // Positive authored motion smaller than modeling tolerance is not an identical source point.
        let tiny = Double.ulpOfOne * 4
        let narrow = try enclosure([points[0], .init(u: tiny, v: 0)], using: &query)
        contains(try narrow.u.coefficient(0, 0), tiny)
        contains(try narrow.u.coefficient(1, 0), tiny)
        #expect(try narrow.u.coefficient(1, 0).lower > 0)
    }

    private func isResource(_ error: any Error, _ resource: ExactResource) -> Bool {
        guard let scalar = geometryTestOriginalFailure(error) as? ExactScalarFailure,
            case .resourceLimit(let actual) = scalar else { return false }
        return actual == resource
    }

    @Test
    func aThirdAuthoredPointStillRequiresTheOriginalJoinProof() throws {
        var query = try execution(OriginalQueryBudget(workLimit: 262_144))
        geometryTestExpectFailure({ geometryTestKernelFailure($0)?.code == .singularGeometry }) {
            try enclosure([.init(u: 0, v: 0), .init(u: 1, v: 0), .init(u: 1, v: 1)],
                spans: 2, algebra: 32, using: &query)
        }
    }

    @Test
    func exactWorkAndBytesRemainCumulativeAtTheCallerBoundary() throws {
        let points = [SurfaceParameter(u: 0.125, v: -0.25), SurfaceParameter(u: 1.125, v: 0.75)]
        var measuring = try execution(OriginalQueryBudget())
        _ = try enclosure(points, using: &measuring)
        let complete = measuring.budget.snapshot
        #expect(complete.work > 0 && complete.storageBytes > 0)
        var exact = try execution(OriginalQueryBudget(workLimit: complete.work,
            storageByteLimit: complete.storageBytes))
        _ = try enclosure(points, using: &exact)
        #expect(exact.budget.snapshot.work == complete.work)
        #expect(exact.budget.snapshot.storageBytes == complete.storageBytes)
        var workShort = try execution(OriginalQueryBudget(workLimit: complete.work - 1))
        geometryTestExpectFailure({ isResource($0, .work) }) { try enclosure(points, using: &workShort) }
        var bytesShort = try execution(OriginalQueryBudget(storageByteLimit: complete.storageBytes - 1))
        geometryTestExpectFailure({ isResource($0, .storage) }) { try enclosure(points, using: &bytesShort) }
        var noBytes = try execution(OriginalQueryBudget(storageByteLimit: 0))
        geometryTestExpectFailure({ isResource($0, .storage) }) { try enclosure(points, using: &noBytes) }
    }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let cancelAt: Int?
        init(cancelAt: Int? = nil) { self.cancelAt = cancelAt }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let ordinal = state.withLock { $0 += 1; return $0 }
            if ordinal == cancelAt { throw .cancelled }
        }
    }

    @Test
    func entryAndTerminalCancellationCannotPublishTheAffineLaw() throws {
        let points = [SurfaceParameter(u: 0, v: 0), SurfaceParameter(u: 1, v: 1)]
        let checkpoints = Checkpoints()
        var measuring = try execution(OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() }))
        _ = try enclosure(points, using: &measuring)
        let complete = measuring.budget.snapshot
        #expect(checkpoints.count > 1)
        for stop in [1, checkpoints.count] {
            let cancel = Checkpoints(cancelAt: stop)
            var query = try execution(OriginalQueryBudget(checkpoint: { try cancel.checkpoint() }))
            geometryTestExpectFailure(geometryTestIsCancelled) { try enclosure(points, using: &query) }
            #expect(query.budget.snapshot.work == (stop == 1 ? 0 : complete.work))
            #expect(query.budget.snapshot.storageBytes == (stop == 1 ? 0 : complete.storageBytes))
        }
    }

    private func planarBound(reversed: Bool, offset: Double = 0,
        using execution: inout OriginalQueryExecution) throws -> Double {
        // This is edge zero from the genuine PlanarSheetTestFixture source, not a replacement spline.
        let a = SurfaceParameter(u: -0.010 + offset, v: 0.020)
        let b = SurfaceParameter(u: -0.010 + offset, v: -0.020)
        return try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(
            curve: .line(.init(origin: .init(x: -0.020, y: -0.010, z: 0), direction: .unitX)),
            from: reversed ? 0.040 : 0, to: reversed ? 0 : 0.040,
            surface: .plane(.init(origin: .origin, normal: .unitZ)),
            parameterCurve: .polyline(reversed ? [b, a] : [a, b]),
            options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 65_536,
                maximumDeviation: ModelingTolerance.standard.distance),
            tolerance: .standard, maximumSpanCount: 64, maximumSubdivisionDepth: 32,
            remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
    }

    private func lift(_ points: [SurfaceParameter], z: Double = 0) -> Curve3D {
        .surfaceLift(.init(surface: .plane(.init(origin: .init(x: 0, y: 0, z: z), normal: .unitZ)),
            parameterCurve: .polyline(points)))
    }

    @Test
    func planarAffineContinuityReceiptRetainsItsSourceAndRefusesForeignReadPremises() throws {
        let points = [SurfaceParameter(u: 0, v: 0), SurfaceParameter(u: 1, v: 1)]
        var query = try execution(OriginalQueryBudget(workLimit: 262_144))
        let source = lift(points)
        let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: .standard,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 0, using: &query)
        let receipt = try geometryTestRequire(prepared.admittingContinuousFirstOrder(
            over: .init(lower: 0, upper: 1), tolerance: .standard, maximumSubdivisionDepth: 32,
            remainingSourceDepth: 16, using: &query))
        #expect(receipt.parameters == (try .init(lower: 0, upper: 1)))
        // The only source authority comes from the retained preparation; no foreign source argument exists.
        guard case .surfaceLift(let retained) = receipt.prepared.curve,
            case .plane(let host) = retained.surface, case .polyline(let retainedPoints) = retained.parameterCurve else {
            Issue.record("The continuity receipt lost its original lifted source."); return
        }
        #expect(host.origin == .origin && host.normal == .unitZ && retainedPoints == points)
        let owners = try receipt.prepared.closedNativeJets(over: receipt.parameters, tolerance: .standard, using: &query)
        let owner = try #require(owners.spans.first)
        contains(owner.jet.z.value, 0)
        #expect(owner.jet.z.value.upper < 1)
        let foreign = try PreparedCurveDifferentialEncloser(curve: lift(points, z: 1), tolerance: .standard,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 0, using: &query)
        let foreignReceipt = try geometryTestRequire(foreign.admittingContinuousFirstOrder(
            over: receipt.parameters, tolerance: .standard, maximumSubdivisionDepth: 32,
            remainingSourceDepth: 16, using: &query))
        let foreignOwners = try foreignReceipt.prepared.closedNativeJets(over: receipt.parameters,
            tolerance: .standard, using: &query)
        let foreignOwner = try #require(foreignOwners.spans.first)
        contains(foreignOwner.jet.z.value, 1)
        #expect(foreignOwner.jet.z.value.lower > 0)
        let changedTolerance = ModelingTolerance(distance: ModelingTolerance.standard.distance * 2,
            angle: ModelingTolerance.standard.angle, relative: ModelingTolerance.standard.relative)
        geometryTestExpectFailure({ geometryTestKernelFailure($0)?.code == .invalidInput }) {
            try prepared.admittingContinuousFirstOrder(over: receipt.parameters, tolerance: changedTolerance,
                maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &query)
        }
        for range in [try ScalarInterval(lower: -0.25, upper: 0.5), try ScalarInterval(lower: 0.5, upper: 1.25)] {
            #expect(throws: GeometryConversionError.self) {
                try prepared.admittingContinuousFirstOrder(over: range, tolerance: .standard,
                    maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &query)
            }
        }
        #expect(throws: GeometryConversionError.self) {
            try prepared.admittingContinuousFirstOrder(over: receipt.parameters, tolerance: .standard,
                maximumSubdivisionDepth: 32, remainingSourceDepth: 0, using: &query)
        }
        var shallow = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32, remainingSourceDepth: 0))
        geometryTestExpectFailure({ geometryTestQueryFailure($0)?.context.resource?.axis == .sourceDepth }) {
            try prepared.admittingContinuousFirstOrder(over: receipt.parameters, tolerance: .standard,
                maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &shallow)
        }
        let unsupported = try PreparedCurveDifferentialEncloser(curve: lift([points[0], .init(u: 1, v: 0), points[1]]),
            tolerance: .standard, remainingSourceDepth: 16, maximumSubdivisionDepth: 32,
            maximumAlgebraicDepth: 32, using: &query)
        let unsupportedReceipt = try unsupported.admittingContinuousFirstOrder(over: receipt.parameters,
            tolerance: .standard, maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &query)
        #expect(unsupportedReceipt == nil)
    }

    @Test(arguments: [false, true])
    func actualPlanarLineCoedgeRetainsTheWholeDirectedCorrespondence(_ reversed: Bool) throws {
        var query = try execution(OriginalQueryBudget(workLimit: 262_144))
        let bound = try planarBound(reversed: reversed, using: &query)
        #expect(bound >= 0 && bound <= ModelingTolerance.standard.distance)
        #expect(query.budget.snapshot.work > 0)
        var wrong = try execution(OriginalQueryBudget(workLimit: 262_144))
        geometryTestExpectFailure({ geometryTestKernelFailure($0)?.code == .topologyFailure }) {
            try planarBound(reversed: reversed, offset: ModelingTolerance.standard.distance * 8,
                using: &wrong)
        }
    }
}
