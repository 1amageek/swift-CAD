import CADCore
@testable import CADGeometry
import Testing

@Suite("Original single-span Native ruled intersection source")
struct OriginalRuledIntersectionSourceTests {
    private enum Failure: Error { case work, storage, unexpectedCell }
    private struct Budget: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var work = 0, words = 0, storageCalls = 0
        var maximumWork = 10_000_000, maximumWords = 10_000_000
        var cancelAtStorageCall: Int?
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try checkpoint()
            try proofScopes.checkWork(count)
            do {
            guard count >= 0, count <= maximumWork - work else { throw Failure.work }
            work += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            proofScopes.recordWork(count)
            try checkpoint()
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try checkpoint()
            let count = try geometryTestStorageWords(bytes)
            do {
            guard count >= 0, count <= maximumWords - words else { throw Failure.storage }
            words += count; storageCalls += 1
            if storageCalls == cancelAtStorageCall { withUnsafeCurrentTask { $0?.cancel() } }
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        
        
            mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            do {
                switch (axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth) ? ExactScalarRootAxis.coefficient : .value {
                case .value:
                    let depth = mapped.value
 throw Failure.unexpectedCell 
                case .coefficient:
                    let depth = mapped.coefficient
 throw Failure.unexpectedCell 
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
    }
    private let tolerance = ModelingTolerance(distance: 1e-9, angle: 1e-10)

    private func source() -> RuledSurface3D {
        .init(startBoundary: .bSpline(.init(degree: 1, knots: [2, 2, 5, 5],
            controlPoints: [.origin, .init(x: 6, y: 0, z: 0)], weights: [1, 2])),
            endBoundary: .bSpline(.init(degree: 1, knots: [1, 1, 6, 6],
                controlPoints: [.init(x: 0, y: 2, z: 3), .init(x: 5, y: 2, z: 3)], weights: [2, 1])),
            uDomain: .closed(2, 5))
    }
    private func box(_ u0: Double = 2, _ u1: Double = 5,
        _ v0: Double = 0, _ v1: Double = 1) throws -> SurfaceParameterBox {
        try .init(u: .init(lower: u0, upper: u1), v: .init(lower: v0, upper: v1))
    }
    private func issue(_ source: RuledSurface3D? = nil, domain: SurfaceParameterBox? = nil,
        depth: Int = 1, usage: inout Budget) throws -> OriginalRuledSurfacePolynomial {
        try .init(source: source ?? self.source(), over: domain ?? box(),
            remainingSourceDepth: depth, tolerance: tolerance, usage: &usage)
    }
    private func q(_ value: Double, _ usage: inout Budget) throws -> ExactRationalCoefficient {
        try .originalDouble(value, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func varyingWeightsUseSameNativeUAndUnreducedDenominators() throws {
        var usage = Budget()
        let receipt = try issue(usage: &usage)
        #expect(receipt.start.spanIndex == 1 && receipt.end.spanIndex == 1)
        #expect(receipt.start.originalTranslation == 0 && receipt.end.originalTranslation == 0)
        #expect(receipt.uDomain.lower == (try q(2, &usage)))
        #expect(receipt.uDomain.upper == (try q(5, &usage)))
        #expect(receipt.denominator == (try receipt.start.homogeneous[3]
            .multiplied(by: receipt.end.homogeneous[3], usage: &usage)))
        for station in [2.0, 3.0, 5.0] {
            let u = try q(station, &usage)
            let a = try u.subtracting(q(2, &usage), usage: &usage).divided(by: q(3, &usage), usage: &usage)
            let b = try u.subtracting(.one, usage: &usage).divided(by: q(5, &usage), usage: &usage)
            let wa = try ExactRationalCoefficient.one.adding(a, usage: &usage)
            let wb = try q(2, &usage).subtracting(b, usage: &usage)
            let ax = try q(12, &usage).multiplied(by: a, usage: &usage).divided(by: wa, usage: &usage)
            let bx = try q(5, &usage).multiplied(by: b, usage: &usage).divided(by: wb, usage: &usage)
            for fraction in [0.0, 0.25, 1.0] {
                let v = try q(fraction, &usage)
                let w = try receipt.denominator.evaluated(atU: u, v: v, usage: &usage)
                let expectedWeight = try wa.multiplied(by: wb, usage: &usage)
                #expect(w.isPositive && w == expectedWeight)
                let expectedX = try ax.adding(bx.subtracting(ax, usage: &usage)
                    .multiplied(by: v, usage: &usage), usage: &usage)
                let x = try receipt.homogeneous[0].evaluated(atU: u, v: v, usage: &usage)
                    .divided(by: w, usage: &usage)
                #expect(x == expectedX)
                #expect(try receipt.homogeneous[1].evaluated(atU: u, v: v, usage: &usage)
                    .divided(by: w, usage: &usage) == q(2, &usage).multiplied(by: v, usage: &usage))
                #expect(try receipt.homogeneous[2].evaluated(atU: u, v: v, usage: &usage)
                    .divided(by: w, usage: &usage) == q(3, &usage).multiplied(by: v, usage: &usage))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func quadraticAndCubicPositiveWeightSourcesKeepRawDegree() throws {
        var usage = Budget()
        let a = BSplineCurve3D(degree: 2, knots: [-2, -2, -2, 4, 4, 4],
            controlPoints: [.origin, .init(x: 3, y: 1, z: 0), .init(x: 6, y: 0, z: 0)], weights: [1, 2, 1])
        let b = BSplineCurve3D(degree: 3, knots: [-2, -2, -2, -2, 4, 4, 4, 4],
            controlPoints: [.init(x: 0, y: 2, z: 3), .init(x: 2, y: 2, z: 3),
                .init(x: 4, y: 2, z: 3), .init(x: 6, y: 2, z: 3)], weights: [1, 2, 3, 4])
        let receipt = try issue(.init(startBoundary: .bSpline(a), endBoundary: .bSpline(b),
            uDomain: .closed(-2, 4)), domain: box(-2, 4), usage: &usage)
        #expect(receipt.start.source.degree == 2 && receipt.end.source.degree == 3)
        // At the original native midpoint, Bernstein weights are 1/4,1/2,1/4
        // and 1/8,3/8,3/8,1/8. These exact values are independent of the issuer.
        for v in [ExactRationalCoefficient.zero, .one] {
            let w = try receipt.denominator.evaluated(atU: .one, v: v, usage: &usage)
            #expect(w == (try q(3.75, &usage)))
            let x = try receipt.homogeneous[0].evaluated(atU: .one, v: v, usage: &usage)
                .divided(by: w, usage: &usage)
            let exactExpected = v.isZero ? try q(3, &usage)
                : try q(18, &usage).divided(by: q(5, &usage), usage: &usage)
            #expect(x == exactExpected)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func closedSubdomainsCornersAndSourceLifetimeArePreserved() throws {
        var usage = Budget(); let original = source()
        let receipt = try { () throws -> OriginalRuledSurfacePolynomial in
            var native = BSplineCurve3D(degree: 1, knots: [2, 2, 5, 5],
                controlPoints: [.origin, .init(x: 6, y: 0, z: 0)], weights: [1, 2])
            let raw = RuledSurface3D(startBoundary: .bSpline(native), endBoundary: original.endBoundary,
                uDomain: original.uDomain)
            let result = try issue(raw, domain: box(2.5, 4.5, 0.25, 0.75), usage: &usage)
            native.controlPoints[0] = .init(x: 100, y: 100, z: 100)
            native.weights[0] = 100
            return result
        }()
        #expect(receipt.source == original && receipt.start.originalCurve == original.startBoundary)
        #expect(receipt.domain == (try box(2.5, 4.5, 0.25, 0.75)))
        for pair in [(2.0, 0.0), (5.0, 1.0)] {
            let corner = try issue(domain: box(pair.0, pair.0, pair.1, pair.1), usage: &usage)
            #expect(corner.uDomain.lower == corner.uDomain.upper && corner.vDomain.lower == corner.vDomain.upper)
        }
        for outside in [try box(2.nextDown, 5), try box(2, 5.nextUp),
            try box(2, 5, -Double.leastNonzeroMagnitude, 1), try box(2, 5, 0, 1.nextUp)] {
            expectCode(.invalidInput) { _ = try issue(domain: outside, usage: &usage) }
        }
        let overlong = RuledSurface3D(startBoundary: original.startBoundary,
            endBoundary: original.endBoundary, uDomain: .closed(2.nextDown, 5))
        expectCode(.invalidInput) { _ = try issue(overlong, usage: &usage) }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeInvalidUnsupportedAndStructuralDepthFailuresAreAtomic() throws {
        var usage = Budget()
        let raw = source()
        var invalid = BSplineCurve3D(degree: 1, knots: [2, 2, 5, 5],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0)], weights: [0, 1])
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is GeometryError }) {
            _ = try issue(.init(startBoundary: .bSpline(invalid), endBoundary: raw.endBoundary,
                uDomain: raw.uDomain), usage: &usage)
        }
        invalid.weights[0] = 1; invalid.isPeriodic = true
        expectCode(.unsupportedCapability) {
            _ = try issue(.init(startBoundary: .bSpline(invalid), endBoundary: raw.endBoundary,
                uDomain: raw.uDomain), usage: &usage)
        }
        let multi = BSplineCurve3D(degree: 1, knots: [2, 2, 3, 5, 5],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0), .init(x: 2, y: 0, z: 0)])
        expectCode(.unsupportedCapability) {
            _ = try issue(.init(startBoundary: .bSpline(multi), endBoundary: raw.endBoundary,
                uDomain: raw.uDomain), usage: &usage)
        }
        expectCode(.unsupportedCapability) {
            _ = try issue(.init(startBoundary: .line(.init(origin: .origin, direction: .unitX)),
                endBoundary: raw.endBoundary, uDomain: raw.uDomain), usage: &usage)
        }
        expectCode(.resourceLimitExceeded) { _ = try issue(depth: 0, usage: &usage) }
        #expect(try issue(depth: 1, usage: &usage).source == raw)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveAdapterBindsAllThreeEquationsAndBothWeightGuards() throws {
        var usage = Budget(); let ruled = try issue(usage: &usage)
        let curve = try OriginalRationalCurvePolynomial(source: .init(degree: 1,
            knots: [0, 0, 1, 1], controlPoints: [.origin, .init(x: 6, y: 0, z: 0)], weights: [1, 2]),
            spanIndex: 1, tolerance: tolerance, usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        let receipt = try ruled.curveRelation(curve: curve, curveDomain: domain, usage: &usage)
        #expect(receipt.ruled.source == ruled.source)
        guard case .curve(let retained) = receipt.target, case .rational(let laws) = receipt.relation.polynomials else {
            Issue.record("CS lost original source binding."); return
        }
        #expect(retained.source == curve.source && receipt.relation.variableCount == 3)
        #expect(receipt.relation.domains == [domain, ruled.uDomain, ruled.vDomain])
        for values in [[0.0, 2.0, 0.0], [0.5, 3.5, 0.0], [1.0, 5.0, 0.0]] {
            let point = try values.map { try q($0, &usage) }
            for law in laws.prefix(3) { #expect(try law.original.evaluated(at: point, usage: &usage).isZero) }
        }
        let off = try [0.5, 3.5, 1.0].map { try q($0, &usage) }
        #expect(try !laws[2].original.evaluated(at: off, usage: &usage).isZero)
        try checkGuards(receipt.relation, usage: &usage)
        let outside = try OriginalRationalParameterDomain(lower: .one.negated, upper: .one, usage: &usage)
        expectCode(.invalidInput) { _ = try ruled.curveRelation(curve: curve, curveDomain: outside, usage: &usage) }
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceAdapterPreservesFourNativeCoordinatesAndOriginalSurface() throws {
        var usage = Budget()
        let a = BSplineCurve3D(degree: 1, knots: [2, 2, 5, 5],
            controlPoints: [.origin, .init(x: 3, y: 0, z: 0)])
        let b = BSplineCurve3D(degree: 1, knots: [2, 2, 5, 5],
            controlPoints: [.init(x: 0, y: 2, z: 0), .init(x: 3, y: 2, z: 0)])
        let ruled = try issue(.init(startBoundary: .bSpline(a), endBoundary: .bSpline(b),
            uDomain: .closed(2, 5)), usage: &usage)
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [7, 7, 10, 10], vKnots: [-2, -2, 0, 0],
            controlPoints: [[.origin, .init(x: 3, y: 0, z: 0)],
                [.init(x: 0, y: 2, z: 0), .init(x: 3, y: 2, z: 0)]])
        let domain = try box(7, 10, -2, 0)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
            using: &usage)
        let spans = try prepared.originalIntersectionNativeSpans(over: domain, tolerance: tolerance,
            using: &usage)
        let native = try #require(spans.first)
        let law = try OriginalRationalSurfacePolynomial(source: surface, native: native,
            domain: domain, view: .unitZ, tolerance: tolerance, usage: &usage)
        let receipt = try ruled.surfaceRelation(surface: law, usage: &usage)
        guard case .surface(let retained) = receipt.target, case .rational(let laws) = receipt.relation.polynomials else {
            Issue.record("SSI lost original source binding."); return
        }
        #expect(retained.source == surface && receipt.relation.variableCount == 4)
        #expect(receipt.relation.domains[2].lower == (try q(7, &usage)))
        #expect(receipt.relation.domains[3].lower == (try q(-2, &usage)))
        for values in [[2.0, 0.0, 7.0, -2.0], [3.5, 0.5, 8.5, -1.0], [5.0, 1.0, 10.0, 0.0]] {
            let point = try values.map { try q($0, &usage) }
            for law in laws.prefix(3) { #expect(try law.original.evaluated(at: point, usage: &usage).isZero) }
        }
        let off = try [3.5, 0.5, 7.0, -1.0].map { try q($0, &usage) }
        #expect(try !laws[0].original.evaluated(at: off, usage: &usage).isZero)
        try checkGuards(receipt.relation, usage: &usage)
    }

    private func checkGuards(_ relation: OriginalPolynomialRelation, usage: inout Budget) throws {
        try RationalAlgebraStorage.retain(relation.predicate.original.maximumStackCount, of: Bool.self, usage: &usage)
        var scratch: [Bool] = []; scratch.reserveCapacity(relation.predicate.original.maximumStackCount)
        #expect(try relation.predicate.original.evaluate(signs: [.zero, .zero, .zero, .positive, .positive],
            scratch: &scratch, usage: &usage))
        for signs: [ExactAlgebraicRealRoot.Sign] in [[.zero, .zero, .zero, .zero, .positive],
            [.zero, .zero, .zero, .positive, .zero], [.zero, .zero, .positive, .positive, .positive]] {
            #expect(try !relation.predicate.original.evaluate(signs: signs, scratch: &scratch, usage: &usage))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func independentCumulativeWorkAndWordLimitsRefuseWithoutReceipt() throws {
        var measured = Budget(); let receipt = try issue(usage: &measured)
        var exact = Budget(maximumWork: measured.work, maximumWords: measured.words)
        #expect(try issue(usage: &exact).homogeneous == receipt.homogeneous)
        var shortWork = Budget(maximumWork: measured.work - 1)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is Failure }) { _ = try issue(usage: &shortWork) }
        var shortWords = Budget(maximumWords: measured.words - 1)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is Failure }) { _ = try issue(usage: &shortWords) }
        let before = measured.work
        measured.maximumWork = before
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is Failure }) { _ = try issue(usage: &measured) }
        #expect(measured.work == before)
    }

    @Test(.timeLimit(.minutes(1)))
    func adaptersShareCallerAdmissionAndRefuseAtFinalStorage() async throws {
        var construction = Budget(); let ruled = try issue(usage: &construction)
        let curve = try OriginalRationalCurvePolynomial(source: .init(degree: 1,
            knots: [0, 0, 1, 1], controlPoints: [.origin, .init(x: 6, y: 0, z: 0)]),
            spanIndex: 1, tolerance: tolerance, usage: &construction)
        let domain = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &construction)
        var measured = Budget()
        _ = try ruled.curveRelation(curve: curve, curveDomain: domain, usage: &measured)
        var exact = Budget(maximumWork: measured.work, maximumWords: measured.words)
        #expect(try ruled.curveRelation(curve: curve, curveDomain: domain, usage: &exact).relation.variableCount == 3)
        var shortWork = Budget(maximumWork: measured.work - 1)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is Failure }) { _ = try ruled.curveRelation(curve: curve, curveDomain: domain, usage: &shortWork) }
        var shortWords = Budget(maximumWords: measured.words - 1)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is Failure }) { _ = try ruled.curveRelation(curve: curve, curveDomain: domain, usage: &shortWords) }
        let finalCall = measured.storageCalls
        let cancelled = try await Task {
            var usage = Budget(cancelAtStorageCall: finalCall)
            do { _ = try ruled.curveRelation(curve: curve, curveDomain: domain, usage: &usage); return false }
            catch let error where geometryTestIsCancelled(error) { return true }
        }.value
        #expect(cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationAtEntryAndFinalStorageCannotPublishSource() async throws {
        var measured = Budget(); _ = try issue(usage: &measured)
        for entry in [true, false] {
            let finalCall = measured.storageCalls
            let cancelled = try await Task {
                if entry { withUnsafeCurrentTask { $0?.cancel() } }
                var usage = Budget(cancelAtStorageCall: entry ? nil : finalCall)
                do { _ = try issue(usage: &usage); return false }
                catch let error where geometryTestIsCancelled(error) { return true }
            }.value
            #expect(cancelled)
        }
    }

    private func expectCode(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Original ruled source unexpectedly succeeded.") }
        catch { #expect(OriginalQueryFailure.classification(of: error)?.code == code) }
    }
}
