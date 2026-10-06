import CADCore
import Testing
@testable import CADGeometry

@Suite("Finite original-native intersection chart cover")
struct OriginalNativeSurfaceChartCoverTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v", "both"], ["multi", "negative", "shifted", "reversed"])
    func everySelectedCycleRetainsOriginalSourceEvaluation(axes: String, chart: String) throws {
        var source = try fixture(axes)
        if chart == "shifted" {
            if source.isUPeriodic { source.uPeriodicOrigin = 20 }
            if source.isVPeriodic { source.vPeriodicOrigin = -12 }
        }
        if chart == "reversed" {
            if source.isUPeriodic {
                source.uKnots = source.uKnots.reversed().map { 4 - $0 }
                source.controlPoints = source.controlPoints.map { Array($0.reversed()) }
            }
            if source.isVPeriodic {
                source.vKnots = source.vKnots.reversed().map { 4 - $0 }
                source.controlPoints.reverse()
            }
        }
        try source.validate(tolerance: .standard)
        let original = source
        let range = chart == "negative" ? (-12.5, 8.5) : chart == "shifted" ? (19.5, 40.5) : (0.0, 20.5)
        let query = try box(source.isUPeriodic ? range : (0, 1), source.isVPeriodic ? range : (0, 1))
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: .standard)
        let spans = try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard, consumeWork: {})
        let axisCount = 22
        #expect(spans.count == (axes == "both" ? axisCount * axisCount : axisCount))
        var area = 0.0
        for span in spans {
            let u0 = max(query.u.lower, span.uBounds.lower), u1 = min(query.u.upper, span.uBounds.upper)
            let v0 = max(query.v.lower, span.vBounds.lower), v1 = min(query.v.upper, span.vBounds.upper)
            area += (u1 - u0) * (v1 - v0)
            #expect(span.surface == original && span.tolerance == .standard)
            #expect(span.uBounds.lower == span.originalBaseUBounds.lower + span.originalUTranslation)
            #expect(span.vBounds.lower == span.originalBaseVBounds.lower + span.originalVTranslation)
            #expect(span.originalUTranslation == Double(span.uCycle) * (source.isUPeriodic ? 4 : 0))
            #expect(span.originalVTranslation == Double(span.vCycle) * (source.isVPeriodic ? 4 : 0))
            let u = (u0 + u1) / 2, v = (v0 + v1) / 2
            let jet = try span.pointJet(u: u, v: v, on: source, tolerance: .standard)
            let a = diamond(source.isUPeriodic && chart == "reversed" ? -u : u)
            let b = diamond(source.isVPeriodic && chart == "reversed" ? -v : v)
            let expected = axes == "both" ? Point3D(x: (3 + b.0) * a.0, y: (3 + b.0) * a.1, z: b.1)
                : axes == "u" ? Point3D(x: a.0, y: a.1, z: v) : Point3D(x: b.0, y: b.1, z: u)
            #expect(jet.x.value.lower <= expected.x && expected.x <= jet.x.value.upper)
            #expect(jet.y.value.lower <= expected.y && expected.y <= jet.y.value.upper)
            #expect(jet.z.value.lower <= expected.z && expected.z <= jet.z.value.upper)
            let c = span.uSpanIndex - 1, r = span.vSpanIndex - 1
            let s = u - span.uBounds.lower, t = v - span.vBounds.lower
            let p00 = original.controlPoints[r][c], p10 = original.controlPoints[r][c + 1]
            let p01 = original.controlPoints[r + 1][c], p11 = original.controlPoints[r + 1][c + 1]
            let du = (p10 - p00) * (1 - t) + (p11 - p01) * t
            let dv = (p01 - p00) * (1 - s) + (p11 - p10) * s
            for (component, expectedU, expectedV) in [(jet.x, du.x, dv.x), (jet.y, du.y, dv.y), (jet.z, du.z, dv.z)] {
                #expect(component.derivativeU.lower <= expectedU && expectedU <= component.derivativeU.upper)
                #expect(component.derivativeV.lower <= expectedV && expectedV <= component.derivativeV.upper)
            }
        }
        #expect(area == query.u.width * query.v.width)
        #expect(source == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshWidthRefusalAndClosedSeamOwnersRemainIndependent() throws {
        let source = try fixture("both")
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: .standard)
        let range = try box((0, 4.5), (0, 1))
        expectCode(.unsupportedCapability) { _ = try prepared.originalNativeSpans(over: range, tolerance: .standard) }
        #expect(try prepared.originalIntersectionNativeSpans(over: range, tolerance: .standard, consumeWork: {}).count == 18)
        for seam in [-12.0, 0, 20] {
            let singleton = try box((seam, seam), (seam, seam))
            let owners = try prepared.originalIntersectionNativeSpans(over: singleton, tolerance: .standard, consumeWork: {})
            #expect(owners.count == 4)
            #expect(Set(owners.map { $0.uCycle }).count == 2)
            #expect(Set(owners.map { $0.vCycle }).count == 2)
            for owner in owners {
                let value = try owner.pointValue(u: seam, v: seam, on: source, tolerance: .standard)
                #expect(value.x.lower <= 4 && 4 <= value.x.upper)
                #expect(value.y.lower <= 0 && 0 <= value.y.upper)
            }
        }
    }

    private enum AdmissionFailure: Error { case work, storage }

    @Test(.timeLimit(.minutes(1)))
    func aggregateSpanWorkAndBytesRefuseWithoutPublishingPartialCover() throws {
        let source = try fixture("both")
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: .standard)
        let query = try box((0.25, 12.5), (-4.5, 8.5))
        let complete = try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard, consumeWork: {})
        expectCode(.resourceLimitExceeded) {
            _ = try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard,
                maximumSpanCount: complete.count - 1, consumeWork: {})
        }
        #expect(try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard,
            maximumSpanCount: complete.count, consumeWork: {}).count == complete.count)
        var work = 0, bytes = 0
        _ = try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard,
            consumeWork: { work += 1 }, consumeStorage: { bytes += $0 })
        #expect(work > complete.count && bytes > complete.count)
        var remainingWork = work - 1
        #expect(throws: AdmissionFailure.work) {
            _ = try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard,
                consumeWork: { remainingWork -= 1; if remainingWork < 0 { throw AdmissionFailure.work } }, consumeStorage: { _ in })
        }
        var remainingBytes = bytes - 1
        #expect(throws: AdmissionFailure.storage) {
            _ = try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard,
                consumeWork: {}, consumeStorage: { remainingBytes -= $0; if remainingBytes < 0 { throw AdmissionFailure.storage } })
        }
        expectCode(.invalidInput) {
            _ = try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard, maximumSpanCount: 0, consumeWork: {})
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func approximatePeriodsUnrepresentableCyclesAndForeignAuthorityRemainFailures() throws {
        var source = try fixture("both")
        source.uKnots[0] = source.uKnots[0].nextUp
        try source.validate(tolerance: .standard)
        let approximate = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: .standard)
        expectCode(.unsupportedCapability) {
            _ = try approximate.originalIntersectionNativeSpans(over: box((0, 20), (0, 1)), tolerance: .standard, consumeWork: {})
        }
        source = try fixture("u")
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: .standard)
        expectCode(.resourceLimitExceeded) {
            _ = try prepared.originalIntersectionNativeSpans(over: box((1e20, 1e20), (0, 1)), tolerance: .standard, consumeWork: {})
        }
        expectCode(.invalidInput) {
            _ = try prepared.originalIntersectionNativeSpans(over: box((0, 20), (-1, 1)), tolerance: .standard, consumeWork: {})
        }
        let token = try #require(try prepared.originalIntersectionNativeSpans(over: box((8.25, 20.5), (0, 1)),
            tolerance: .standard, consumeWork: {}).first)
        var foreign = source; foreign.controlPoints[0][0].z += 0.25
        expectCode(.invalidInput) { _ = try token.pointJet(u: 8.5, v: 0.5, on: foreign, tolerance: .standard) }
        expectCode(.invalidInput) { _ = try token.pointJet(u: 0.5, v: 0.5, on: source, tolerance: .standard) }
        var otherTolerance = ModelingTolerance.standard; otherTolerance.distance *= 2
        expectCode(.invalidInput) {
            _ = try prepared.originalIntersectionNativeSpans(over: box((0, 20), (0, 1)), tolerance: otherTolerance, consumeWork: {})
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationAtFinalStorageAdmissionCannotPublishCover() async throws {
        let source = try fixture("u")
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: .standard)
        let query = try box((0.25, 0.75), (0, 1))
        var reservations = 0
        _ = try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard,
            consumeWork: {}, consumeStorage: { _ in reservations += 1 })
        let lastReservation = reservations
        let task = Task {
            var admitted = 0
            return try prepared.originalIntersectionNativeSpans(over: query, tolerance: .standard,
                consumeWork: {}, consumeStorage: { _ in
                    admitted += 1
                    if admitted == lastReservation { withUnsafeCurrentTask { $0?.cancel() } }
                })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func fixture(_ axes: String) throws -> BSplineSurface3D {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
        let net = axes == "both" ? c.map { b in c.map { a in Point3D(x: (3 + b.0) * a.0, y: (3 + b.0) * a.1, z: b.1) } }
            : axes == "u" ? [0.0, 1.0].map { z in c.map { Point3D(x: $0.0, y: $0.1, z: z) } }
            : c.map { a in [0.0, 1.0].map { z in Point3D(x: a.0, y: a.1, z: z) } }
        return try .periodic(uDegree: 1, vDegree: 1,
            uKnots: axes == "v" ? [0, 0, 1, 1] : [0, 1, 2, 3, 4],
            vKnots: axes == "u" ? [0, 0, 1, 1] : [0, 1, 2, 3, 4],
            controlPoints: net, isUPeriodic: axes != "v", isVPeriodic: axes != "u", tolerance: .standard)
    }

    private func diamond(_ parameter: Double) -> (Double, Double) {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
        let wrapped = parameter - (parameter / 4).rounded(.down) * 4
        let index = Int(wrapped.rounded(.down)), fraction = wrapped - Double(index)
        let a = c[index], b = c[(index + 1) % 4]
        return (a.0 + (b.0 - a.0) * fraction, a.1 + (b.1 - a.1) * fraction)
    }

    private func box(_ u: (Double, Double), _ v: (Double, Double)) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u.0, upper: u.1), v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func expectCode(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Incomplete selected cover was admitted.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Unexpected selected cover error: \(error)") }
    }
}
