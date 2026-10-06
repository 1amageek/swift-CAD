import CADCore
import Testing
@testable import CADGeometry

@Suite("Finite original-native curve chart cover", .timeLimit(.minutes(1)))
struct OriginalNativeCurveChartCoverTests {
    private enum AdmissionFailure: Error { case work, storage }
    private struct Admission: RationalAlgebraAdmitting {
        var work = 0, storage = 0, storageCalls = 0
        var maximumWork = Int.max, maximumStorage = Int.max
        var cancelAtWork: Int? = nil
        var cancelAtStorageCall: Int? = nil
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw AdmissionFailure.work }
            work += count
            if let cancelAtWork, work >= cancelAtWork { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw AdmissionFailure.storage }
            storage += count; storageCalls += 1
            if storageCalls == cancelAtStorageCall { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func visitExactCell(depth: Int) throws {
            Issue.record("Curve chart issuance must not invoke a root solver.")
            throw AdmissionFailure.work
        }
    }

    @Test(arguments: [false, true], ["multi", "negative", "shifted", "reversed"])
    func completeCyclesRetainLiteralOriginalRationalPointAndDerivatives(weighted: Bool, chart: String) throws {
        var source = try fixture(weighted: weighted)
        if chart == "shifted" { source.periodicOrigin = 20 }
        if chart == "reversed" { source = try source.reversed(tolerance: .standard) }
        let original = source
        let range = chart == "negative" ? (-12.5, 8.5) : chart == "shifted" ? (19.5, 40.5) : (0.0, 20.5)
        let query = try interval(range.0, range.1)
        var usage = Admission()
        let cover = try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
            maximumSpanCount: 22, usage: &usage)
        #expect(cover.spans.count == 22)
        #expect(cover.source == original && cover.parameters == query && cover.tolerance == .standard)
        #expect(Set(cover.spans.map(\.cycle)).count > 4)
        var length = 0.0
        for owner in cover.spans {
            length += owner.parameters.width
            #expect(owner.law.source == original)
            #expect(owner.originalTranslation == Double(owner.cycle) * 4)
            #expect(owner.nativeDomain.lower == source.knots[owner.nativeIndex] + owner.originalTranslation)
            #expect(owner.nativeDomain.upper == source.knots[owner.nativeIndex + 1] + owner.originalTranslation)
            for parameter in [owner.parameters.lower, (owner.parameters.lower + owner.parameters.upper) / 2, owner.parameters.upper] {
                let jet = try owner.intervalJet(over: interval(parameter, parameter), on: original,
                    tolerance: .standard, usage: &usage)
                let q = parameter - owner.nativeDomain.lower
                let p0 = original.controlPoints[owner.nativeIndex - 1], p1 = original.controlPoints[owner.nativeIndex]
                let w0 = original.weights[owner.nativeIndex - 1], w1 = original.weights[owner.nativeIndex]
                let d = w0 * (1 - q) + w1 * q, dw = w1 - w0
                let a = Vector3D(x: p0.x, y: p0.y, z: p0.z), b = Vector3D(x: p1.x, y: p1.y, z: p1.z)
                let position = (a * (w0 * (1 - q)) + b * (w1 * q)) / d
                let derivative = (b - a) * (w0 * w1 / (d * d))
                let second = derivative * (-2 * dw / d)
                let third = derivative * (6 * dw * dw / (d * d))
                for (fields, values) in [(jet.x.derivatives, [position.x, derivative.x, second.x, third.x]),
                    (jet.y.derivatives, [position.y, derivative.y, second.y, third.y]),
                    (jet.z.derivatives, [position.z, derivative.z, second.z, third.z])] {
                    for (field, value) in zip(fields, values) { contains(field, value) }
                }
            }
        }
        #expect(length == query.width)
        #expect(source == original)
    }

    @Test(arguments: [-12.0, 0, 20])
    func singletonSeamsRetainBothOriginalOneSidedOwners(seam: Double) throws {
        let source = try fixture()
        var usage = Admission()
        let cover = try OriginalNativeCurveChartCover(source: source, over: interval(seam, seam),
            tolerance: .standard, maximumSpanCount: 2, usage: &usage)
        #expect(cover.spans.count == 2)
        #expect(cover.spans.map(\.nativeIndex) == [4, 1])
        #expect(cover.spans[0].cycle + 1 == cover.spans[1].cycle)
        for owner in cover.spans {
            let jet = try owner.intervalJet(over: interval(seam, seam), on: source, tolerance: .standard, usage: &usage)
            contains(jet.x.value, 1); contains(jet.y.value, 0)
            contains(jet.x.derivatives[1], owner.nativeIndex == 4 ? 1 : -1)
            contains(jet.y.derivatives[1], 1)
        }
        expectCode(.resourceLimitExceeded) {
            _ = try OriginalNativeCurveChartCover(source: source, over: interval(seam, seam),
                tolerance: .standard, maximumSpanCount: 1, usage: &usage)
        }
    }

    @Test
    func openKnotsAndRetainedSelectedSupportKeepOriginalAuthority() throws {
        let source = BSplineCurve3D(degree: 1, knots: [2, 2, 3, 5, 5],
            controlPoints: [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0), .init(x: 1, y: 2, z: 0)])
        var usage = Admission()
        let cover = try OriginalNativeCurveChartCover(source: source, over: interval(3, 3),
            tolerance: .standard, maximumSpanCount: 2, usage: &usage)
        #expect(cover.spans.map(\.nativeIndex) == [1, 2])
        for owner in cover.spans {
            #expect(owner.cycle == 0 && owner.originalTranslation == 0)
            let jet = try owner.intervalJet(over: interval(3, 3), on: source, tolerance: .standard, usage: &usage)
            contains(jet.x.value, 1); contains(jet.y.value, 0)
            contains(jet.x.derivatives[1], owner.nativeIndex == 1 ? 1 : 0)
            contains(jet.y.derivatives[1], owner.nativeIndex == 1 ? 0 : 1)
        }
        expectCode(.invalidInput) {
            _ = try OriginalNativeCurveChartCover(source: source, over: interval(1, 3),
                tolerance: .standard, maximumSpanCount: 2, usage: &usage)
        }
        expectCode(.invalidInput) {
            _ = try cover.spans[0].intervalJet(over: interval(2.5, 2.5), on: source, tolerance: .standard, usage: &usage)
        }
        var foreign = source; foreign.controlPoints[0].z = 1
        expectCode(.invalidInput) {
            _ = try cover.spans[0].intervalJet(over: interval(3, 3), on: foreign, tolerance: .standard, usage: &usage)
        }
        var tolerance = ModelingTolerance.standard; tolerance.distance *= 2
        expectCode(.invalidInput) {
            _ = try cover.spans[0].intervalJet(over: interval(3, 3), on: source, tolerance: tolerance, usage: &usage)
        }
        let retained = try cover.spans[0].intervalJet(over: interval(3, 3), on: cover.source, tolerance: .standard, usage: &usage)
        contains(retained.x.value, 1)
    }

    @Test
    func independentCallerSpanWorkAndStorageLimitsRemainAtomic() throws {
        let source = try fixture(weighted: true), query = try interval(-4.5, 20.5)
        var completeUsage = Admission()
        let cover = try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
            maximumSpanCount: Int.max, usage: &completeUsage)
        #expect(cover.spans.count == 26)
        var limited = Admission()
        expectCode(.resourceLimitExceeded) {
            _ = try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
                maximumSpanCount: cover.spans.count - 1, usage: &limited)
        }
        var exact = Admission()
        #expect(try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
            maximumSpanCount: cover.spans.count, usage: &exact).spans.count == cover.spans.count)
        var work = Admission(maximumWork: completeUsage.work - 1)
        #expect(throws: AdmissionFailure.work) {
            _ = try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
                maximumSpanCount: Int.max, usage: &work)
        }
        var storage = Admission(maximumStorage: completeUsage.storage - 1)
        #expect(throws: AdmissionFailure.storage) {
            _ = try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
                maximumSpanCount: Int.max, usage: &storage)
        }
        expectCode(.invalidInput) {
            _ = try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
                maximumSpanCount: 0, usage: &limited)
        }
    }

    @Test(arguments: ["approximate", "period", "cycle", "endpoint", "tail", "translation", "infinite"])
    func unsupportedAndUnrepresentableSourceDomainsRefuseExplicitly(failure: String) throws {
        var source = try fixture()
        var query = try interval(0, 20)
        if failure == "infinite" {
            expectCode(.invalidInput) { _ = try interval(0, .infinity) }
            return
        }
        if failure == "period" {
            source.knots = [-3, -Double(2).nextUp, -1, 0, 1, 2, 3]
            source.periodicOrigin = source.knots[source.degree]
            try source.validate(tolerance: .standard)
            #expect(source.knots[5] - source.knots[1] == 4 && source.knots[1] < -2)
        }
        if failure == "approximate" { source.knots[0] = source.knots[0].nextUp; try source.validate(tolerance: .standard) }
        if failure == "cycle" { query = try interval(1e20, 1e20) }
        if failure == "endpoint" {
            source = try BSplineCurve3D.periodic(degree: 1, cycleKnots: [0, 0.25, 0.5, 1, 4],
                controlPoints: [.init(x: 1, y: 0, z: 0), .init(x: 0, y: 1, z: 0),
                    .init(x: -1, y: 0, z: 0), .init(x: 0, y: -1, z: 0)], tolerance: .standard)
            query = try interval(4_503_599_627_370_496, 4_503_599_627_370_496)
        }
        if failure == "translation" {
            source = try BSplineCurve3D.periodic(degree: 1, cycleKnots: [0, 1, 2, 3, 4.5],
                controlPoints: [.init(x: 1, y: 0, z: 0), .init(x: 0, y: 1, z: 0),
                    .init(x: -1, y: 0, z: 0), .init(x: 0, y: -1, z: 0)], tolerance: .standard)
            query = try interval(13_510_798_882_111_476, 13_510_798_882_111_476)
        }
        if failure == "tail" { source.controlPoints[4].z = 1 }
        var usage = Admission()
        expectCode((failure == "approximate" || failure == "period") ? .unsupportedCapability : failure == "tail" || failure == "infinite" ? .invalidInput : .resourceLimitExceeded) {
            _ = try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
                maximumSpanCount: 100, usage: &usage)
        }
    }

    @Test(arguments: ["work", "storage", "before"])
    func cancelledIssuerNeverReturnsPartialChartAuthority(boundary: String) async throws {
        let source = try fixture(), query = try interval(0.25, 0.75)
        var baseline = Admission()
        _ = try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
            maximumSpanCount: 1, usage: &baseline)
        let finalWork = baseline.work, finalStorage = baseline.storageCalls
        let task = Task {
            var usage = Admission(cancelAtWork: boundary == "work" ? finalWork : nil,
                cancelAtStorageCall: boundary == "storage" ? finalStorage : nil)
            if boundary == "before" { withUnsafeCurrentTask { $0?.cancel() } }
            return try OriginalNativeCurveChartCover(source: source, over: query, tolerance: .standard,
                maximumSpanCount: 1, usage: &usage)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func fixture(weighted: Bool = false) throws -> BSplineCurve3D {
        try .periodic(degree: 1, cycleKnots: [0, 1, 2, 3, 4],
            controlPoints: [.init(x: 1, y: 0, z: 0), .init(x: 0, y: 1, z: 0),
                .init(x: -1, y: 0, z: 0), .init(x: 0, y: -1, z: 0)],
            weights: weighted ? [1, 2, 4, 2] : nil, tolerance: .standard)
    }
    private func interval(_ lower: Double, _ upper: Double) throws -> ScalarInterval {
        try .init(lower: lower, upper: upper)
    }
    private func contains(_ range: OutwardScalarInterval, _ value: Double) {
        #expect(range.lower <= value && value <= range.upper)
    }
    private func expectCode(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Incomplete curve chart coverage was admitted.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Unexpected curve chart error: \(error)") }
    }
}
