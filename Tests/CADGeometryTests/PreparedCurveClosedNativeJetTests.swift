import CADCore
@testable import CADGeometry
import Foundation
import Synchronization
import Testing

@Suite("Original closed native curve jets", .timeLimit(.minutes(1)))
struct PreparedCurveClosedNativeJetTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func c0QuarterCylinderRailsRetainEveryClosedOwningSpeed() throws {
        let x = [0.0, 0.01, 0.02]
        func rail(y: Double, z: Double) -> Curve3D {
            .bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 0.37, 1, 1],
                controlPoints: x.map { Point3D(x: $0, y: y, z: z) }))
        }
        let center = rail(y: 0, z: 0)
        let first = rail(y: 0.01, z: 0), second = rail(y: 0, z: 0.01)
        let blend = RollingBallBlendSurface3D(centerSpine: center, firstContact: first,
            secondContact: second, radius: 0.01, tolerance: tolerance)
        try blend.validate()
        let work = Mutex(0)
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(consumeWorkUnits: { units in
            work.withLock { $0 += units }
        }), limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        for source in [center, first, second] {
            let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance,
                using: &execution)
            let receipt = try prepared.closedNativeJets(over: interval(0.37, 0.37), tolerance: tolerance,
                using: &execution)
            #expect(receipt.source == source)
            #expect(receipt.spans.map(\.nativeIndex) == [1, 2])
            for (index, speed) in [0.01 / 0.37, 0.01 / 0.63].enumerated() {
                contains(receipt.spans[index].jet.x.value, 0.01)
                contains(receipt.spans[index].jet.x.derivativeU, speed)
                contains(receipt.spans[index].jet.x.secondDerivativeUU, 0)
                contains(receipt.spans[index].jet.x.thirdDerivativeUUU, 0)
            }
            let end = try prepared.closedNativeJets(over: interval(1, 1), tolerance: tolerance,
                using: &execution)
            #expect(end.spans.count == 1)
            contains(end.spans[0].jet.x.value, 0.02)
        }
        // These are actual source section evaluations; area publication is a later consumer proof.
        let lowerContact = try blend.point(u: 0.37, v: 0)
        let upperContact = try blend.point(u: 0.37, v: 1)
        #expect(abs(lowerContact.x - 0.01) < 1e-14)
        #expect(abs(lowerContact.y - 0.01) < 1e-14)
        #expect(abs(upperContact.z - 0.01) < 1e-14)
        // The former 18 high-level callbacks did not count canonical validation and payload work.
        #expect(work.withLock { $0 } == execution.budget.snapshot.work)
        #expect(execution.budget.snapshot.work > 0)
    }

    @Test(arguments: [false, true])
    func unequalWeightsRetainLiteralNativeEndpointAndThirdDerivatives(reversed: Bool) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        var source = BSplineCurve3D(degree: 2, knots: [2, 2, 2, 5, 5, 5],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0, y: 0.5, z: 0), Point3D(x: 1, y: 1, z: 0)],
            weights: [4, 2, 1])
        if reversed { source = try source.reversed(tolerance: tolerance) }
        let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: tolerance, using: &execution)
        for q in [0.0, 0.375, 1.0] {
            let receipt = try prepared.closedNativeJets(over: interval(2 + 3 * q, 2 + 3 * q),
                tolerance: tolerance, using: &execution)
            #expect(receipt.spans.count == 1)
            let t = reversed ? 1 - q : q, d = 2 - t
            let sign = reversed ? -1.0 : 1.0
            let jet = receipt.spans[0].jet
            // N=(t²,t(2-t),0), W=(2-t)²: genuinely non-polynomial rational source.
            let expectedX = [t * t / (d * d), sign * 4 * t / (3 * d * d * d),
                8 * (1 + t) / (9 * pow(d, 4)), sign * 24 * (2 + t) / (27 * pow(d, 5))]
            let expectedY = [t / d, sign * 2 / (3 * d * d),
                4 / (9 * d * d * d), sign * 12 / (27 * pow(d, 4))]
            for (field, value) in zip(fields(jet.x), expectedX) { contains(field, value) }
            for (field, value) in zip(fields(jet.y), expectedY) { contains(field, value) }
            for field in fields(jet.z) { contains(field, 0) }
            #expect(jet.x.value.upper - jet.x.value.lower < 1e-11)
        }
    }

    @Test
    func c0KnotKeepsDistinctOneSidedDirectionAndCurvatureJets() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let source = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 0.37, 0.37, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0),
                Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 1, z: 0), Point3D(x: 3, y: 0, z: 0)])
        let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: tolerance, using: &execution)
        for range in [try interval(0.37, 0.37), try interval(0.2, 0.37)] {
            let receipt = try prepared.closedNativeJets(over: range, tolerance: tolerance, using: &execution)
            #expect(receipt.spans.map(\.nativeIndex) == [2, 4])
            let point = try prepared.closedNativeJets(over: interval(0.37, 0.37), tolerance: tolerance, using: &execution)
            let left = point.spans[0].jet, right = point.spans[1].jet
            contains(left.x.derivativeU, 0); contains(left.y.derivativeU, 2 / 0.37)
            contains(right.x.derivativeU, 2 / 0.63); contains(right.y.derivativeU, 0)
            contains(left.x.secondDerivativeUU, -2 / (0.37 * 0.37))
            contains(left.y.secondDerivativeUU, 2 / (0.37 * 0.37))
            contains(right.y.secondDerivativeUU, -2 / (0.63 * 0.63))
            #expect(left.x.derivativeU.upper < right.x.derivativeU.lower)
            #expect(left.y.secondDerivativeUU.lower > right.y.secondDerivativeUU.upper)
        }
        // The legacy positive entry must also retain the side that only touches its endpoint.
        let union = try prepared.thirdOrderIntervalJet(over: interval(0.2, 0.37), tolerance: tolerance)
        contains(union.x.derivativeU, 2 / 0.63)
    }

    @Test
    func nonBezierNativeSpanIsCertifiedFromOriginalBasisRatherThanRoundedPatch() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let source = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 0.37, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0),
                Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 1, z: 0)])
        let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: tolerance, using: &execution)
        let result = try prepared.closedNativeJets(over: interval(0.37 / 2, 0.37 / 2),
            tolerance: tolerance, using: &execution)
        let jet = try #require(result.spans.first).jet
        // The first original span is exactly [(0,0),(1,0),(1,.37)] in Bernstein form.
        contains(jet.x.value, 0.75); contains(jet.y.value, 0.37 / 4)
        contains(jet.x.derivativeU, 1 / 0.37); contains(jet.y.derivativeU, 1)
        contains(jet.x.secondDerivativeUU, -2 / (0.37 * 0.37))
        contains(jet.y.secondDerivativeUU, 2 / 0.37)
        contains(jet.x.thirdDerivativeUUU, 0)
    }

    @Test
    func preparationAndClosedQueriesUseTheSameCallerWorkAndExactTolerance() throws {
        let source = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 0.37, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.01, y: 0, z: 0), Point3D(x: 0.02, y: 0, z: 0)]))
        var baseline = try OriginalQueryExecution.independentGeometry()
        let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance, using: &baseline)
        let preparationWork = baseline.budget.snapshot.work
        let complete = try prepared.closedNativeJets(over: interval(0.37, 0.37), tolerance: tolerance, using: &baseline)
        let completeWork = baseline.budget.snapshot.work
        #expect(complete.spans.map(\.nativeIndex) == [1, 2])
        #expect(preparationWork > 0 && completeWork > preparationWork)
        // Historical prelude 3 / ceiling 4 were callback units, not cumulative canonical work.
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: completeWork - 1),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let limited = try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance, using: &execution)
        #expect(execution.budget.snapshot.work == preparationWork)
        do {
            _ = try limited.closedNativeJets(over: interval(0.37, 0.37), tolerance: tolerance, using: &execution)
            Issue.record("Both owning sides must consume the same aggregate caller budget.")
        } catch {
            guard let scalar = geometryTestOriginalFailure(error) as? ExactScalarFailure,
                case .resourceLimit(.work) = scalar else { throw error }
            #expect(execution.budget.snapshot.work < completeWork)
        }
        let foreignTolerance = ModelingTolerance(distance: tolerance.distance * 2, angle: tolerance.angle, relative: tolerance.relative)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try prepared.closedNativeJets(over: interval(0, 0), tolerance: foreignTolerance, using: &baseline)
        }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try prepared.closedNativeJets(over: interval(-0.01, 0), tolerance: tolerance, using: &baseline)
        }
    }

    @Test
    func cancellationDoesNotPublishAnOwningReceipt() async throws {
        let source = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)]))
        let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var execution = try OriginalQueryExecution.independentGeometry()
            return try prepared.closedNativeJets(over: interval(0.5, 0.5), tolerance: tolerance, using: &execution)
        }
        do { _ = try await task.value; Issue.record("Cancelled closed curve queries must fail.") }
        catch where geometryTestIsCancelled(error) { }
    }

    private func interval(_ lower: Double, _ upper: Double) throws -> ScalarInterval {
        try ScalarInterval(lower: lower, upper: upper)
    }
    private func fields(_ jet: SurfaceIntervalJet) -> [OutwardScalarInterval] {
        [jet.value, jet.derivativeU, jet.secondDerivativeUU, jet.thirdDerivativeUUU]
    }
    private func contains(_ interval: OutwardScalarInterval, _ value: Double) {
        #expect(interval.isFinite)
        #expect(interval.lower <= value)
        #expect(interval.upper >= value)
    }
}
