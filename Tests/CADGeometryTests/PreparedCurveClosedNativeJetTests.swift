import CADCore
@testable import CADGeometry
import Foundation
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
        var work = 0
        for source in [center, first, second] {
            let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance,
                consumeWork: { work += 1 })
            let receipt = try prepared.closedNativeJets(over: interval(0.37, 0.37), tolerance: tolerance,
                consumeWork: { work += 1 })
            #expect(receipt.source == source)
            #expect(receipt.spans.map(\.nativeIndex) == [1, 2])
            for (index, speed) in [0.01 / 0.37, 0.01 / 0.63].enumerated() {
                contains(receipt.spans[index].jet.x.value, 0.01)
                contains(receipt.spans[index].jet.x.derivativeU, speed)
                contains(receipt.spans[index].jet.x.secondDerivativeUU, 0)
                contains(receipt.spans[index].jet.x.thirdDerivativeUUU, 0)
            }
            let end = try prepared.closedNativeJets(over: interval(1, 1), tolerance: tolerance,
                consumeWork: { work += 1 })
            #expect(end.spans.count == 1)
            contains(end.spans[0].jet.x.value, 0.02)
        }
        // These are actual source section evaluations; area publication is a later consumer proof.
        let lowerContact = try blend.point(u: 0.37, v: 0)
        let upperContact = try blend.point(u: 0.37, v: 1)
        #expect(abs(lowerContact.x - 0.01) < 1e-14)
        #expect(abs(lowerContact.y - 0.01) < 1e-14)
        #expect(abs(upperContact.z - 0.01) < 1e-14)
        #expect(work == 18)
    }

    @Test(arguments: [false, true])
    func unequalWeightsRetainLiteralNativeEndpointAndThirdDerivatives(reversed: Bool) throws {
        var source = BSplineCurve3D(degree: 2, knots: [2, 2, 2, 5, 5, 5],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0, y: 0.5, z: 0), Point3D(x: 1, y: 1, z: 0)],
            weights: [4, 2, 1])
        if reversed { source = try source.reversed(tolerance: tolerance) }
        let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: tolerance)
        for q in [0.0, 0.375, 1.0] {
            let receipt = try prepared.closedNativeJets(over: interval(2 + 3 * q, 2 + 3 * q),
                tolerance: tolerance, consumeWork: {})
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
        let source = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 0.37, 0.37, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0),
                Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 1, z: 0), Point3D(x: 3, y: 0, z: 0)])
        let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: tolerance)
        for range in [try interval(0.37, 0.37), try interval(0.2, 0.37)] {
            let receipt = try prepared.closedNativeJets(over: range, tolerance: tolerance, consumeWork: {})
            #expect(receipt.spans.map(\.nativeIndex) == [2, 4])
            let point = try prepared.closedNativeJets(over: interval(0.37, 0.37), tolerance: tolerance, consumeWork: {})
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
        let source = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 0.37, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0),
                Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 1, z: 0)])
        let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: tolerance)
        let result = try prepared.closedNativeJets(over: interval(0.37 / 2, 0.37 / 2),
            tolerance: tolerance, consumeWork: {})
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
        var work = 0
        func consume() throws {
            work += 1
            if work > 4 { throw KernelError(phase: .geometry, code: .resourceLimitExceeded, residual: Double(work), tolerance: tolerance, message: "Test caller work exhausted.") }
        }
        let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance, consumeWork: consume)
        #expect(work == 3)
        do {
            _ = try prepared.closedNativeJets(over: interval(0.37, 0.37), tolerance: tolerance, consumeWork: consume)
            Issue.record("Both owning sides must consume the same aggregate caller budget.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded); #expect(error.residual == 5) }
        let foreignTolerance = ModelingTolerance(distance: tolerance.distance * 2, angle: tolerance.angle, relative: tolerance.relative)
        #expect(throws: KernelError.self) {
            try prepared.closedNativeJets(over: interval(0, 0), tolerance: foreignTolerance, consumeWork: {})
        }
        #expect(throws: KernelError.self) {
            try prepared.closedNativeJets(over: interval(-0.01, 0), tolerance: tolerance, consumeWork: {})
        }
    }

    @Test
    func cancellationDoesNotPublishAnOwningReceipt() async throws {
        let source = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)]))
        let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try prepared.closedNativeJets(over: interval(0.5, 0.5), tolerance: tolerance, consumeWork: {})
        }
        do { _ = try await task.value; Issue.record("Cancelled closed curve queries must fail.") }
        catch is CancellationError { }
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
