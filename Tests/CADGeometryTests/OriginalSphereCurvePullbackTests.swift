import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite("Original authored sphere curve pullback")
struct OriginalSphereCurvePullbackTests {
    private final class Budget: Sendable {
        private struct State { var work = 0, storage = 0, storageCalls = 0, cells = 0 }
        private let state = Mutex(State())
        private let maximumWork: Int
        private let maximumStorage: Int
        private let cancelAtStorageCall: Int?
        init(work: Int = 10_000_000, storage: Int = 10_000_000, cancelAtStorageCall: Int? = nil) {
            maximumWork = work; maximumStorage = storage; self.cancelAtStorageCall = cancelAtStorageCall
        }
        var spent: (work: Int, storage: Int, storageCalls: Int, cells: Int) {
            state.withLock { ($0.work, $0.storage, $0.storageCalls, $0.cells) }
        }
        var usage: GeometryTestScalarRecorder {
            .init(maximumValueDepth: 24, maximumCoefficientDepth: 24, observeWork: { count in
                try self.state.withLock { state in
                    guard count <= self.maximumWork - state.work else { throw Self.exhausted() }
                    state.work += count
                }
            }, observeStorageWords: { count in
                let cancel = try self.state.withLock { state in
                    guard count <= self.maximumStorage - state.storage else { throw Self.exhausted() }
                    state.storage += count; state.storageCalls += 1
                    return state.storageCalls == self.cancelAtStorageCall
                }
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }, observeValueCell: { depth in
                try self.state.withLock { state in
                    guard depth <= 24 else { throw Self.exhausted() }; state.cells += 1
                }
            }, observeCoefficientCell: { _ in
                Issue.record("A rational sphere source cannot invent coefficient roots.")
                throw Self.exhausted()
            })
        }
        private static func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Sphere source test exhausted independent caller admission.")
        }
    }

    private let sphere = AnalyticSurface3D.sphere(center: .origin, radius: 1)
    private let tolerance = ModelingTolerance(distance: 1e-9, angle: 1e-10)
    private let resolver: any OriginalPolynomialRelationResolving = DefaultOriginalPolynomialRelationResolver()

    private func tangentSource(weight: Double = 1, lower: Double = 0, upper: Double = 1) -> BSplineCurve3D {
        .init(degree: 1, knots: [lower, lower, upper, upper],
            controlPoints: [.init(x: -2, y: 1, z: 0), .init(x: 2, y: 1, z: 0)], weights: [1, weight])
    }

    private func curveLaw(_ source: BSplineCurve3D, usage: inout GeometryTestScalarRecorder)
        throws -> OriginalRationalCurvePolynomial {
        try .init(source: source, spanIndex: source.degree, tolerance: tolerance, usage: &usage)
    }

    private func decompose(_ pullback: OriginalSphereCurvePullback, budget: Budget) throws -> OriginalRealRelation {
        var usage = budget.usage
        let relation = try pullback.relation(usage: &usage)
        return try resolver.decompose(relation, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func rawTangentRetainsRepeatedRootAndPublicOriginalRelation() throws {
        let budget = Budget(); var usage = budget.usage
        let native = try curveLaw(tangentSource(), usage: &usage)
        let pullback = try OriginalSphereCurvePullback(sphere: sphere, curve: native,
            tolerance: tolerance, usage: &usage)
        let t = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let linear = try t.scaled(by: .originalDouble(4, usage: &usage), usage: &usage)
            .subtracting(.constant(.originalDouble(2, usage: &usage), usage: &usage), usage: &usage)
        #expect(pullback.equation == (try linear.multiplied(by: linear, usage: &usage)))
        #expect(pullback.equation.uDegree == 2 && pullback.denominator == native.homogeneous[3])
        #expect(budget.spent.cells == 0)
        let result = try decompose(pullback, budget: budget)
        let half = try ExactRationalCoefficient.one.divided(by: .originalDouble(2, usage: &usage), usage: &usage)
        #expect(result.cells.count == 1 && result.components.count == 1 && result.cells[0].dimension == 0)
        #expect(try result.contains(rationalPoint: [half], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
        #expect(try !result.contains(rationalPoint: [.zero], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func translatedNonunitSphereRetainsSourceCoefficientsAndTangent() throws {
        let budget = Budget(); var usage = budget.usage
        let authored = AnalyticSurface3D.sphere(center: .init(x: 2, y: -3, z: 5), radius: 1.5)
        let source = BSplineCurve3D(degree: 1, knots: [-4, -4, 2, 2], controlPoints: [
            .init(x: 0, y: -1.5, z: 5), .init(x: 4, y: -1.5, z: 5)])
        let native = try curveLaw(source, usage: &usage)
        let pullback = try OriginalSphereCurvePullback(sphere: authored, curve: native,
            tolerance: tolerance, usage: &usage)
        #expect(pullback.sphere == authored && pullback.curve.source == source)
        #expect(pullback.domain.lower == (try .originalDouble(-4, usage: &usage)))
        #expect(pullback.domain.upper == (try .originalDouble(2, usage: &usage)))
        #expect(pullback.denominator == native.homogeneous[3])
        let twoThirds = try ExactRationalCoefficient.originalDouble(2, usage: &usage)
            .divided(by: .originalDouble(3, usage: &usage), usage: &usage)
        let linear = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .adding(.constant(.one, usage: &usage), usage: &usage)
            .scaled(by: twoThirds, usage: &usage)
        #expect(pullback.equation == (try linear.multiplied(by: linear, usage: &usage)))
        let result = try decompose(pullback, budget: budget)
        #expect(result.cells.count == 1 && result.components.count == 1 && result.cells[0].dimension == 0)
        #expect(try result.contains(rationalPoint: [.one.negated], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
        #expect(try !result.contains(rationalPoint: [.zero], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func varyingWeightsKeepNonunitParameterDomainAndReleasedSource() throws {
        let budget = Budget(); var usage = budget.usage
        let expectedSource = tangentSource(weight: 2, lower: 2, upper: 5)
        let pullback: OriginalSphereCurvePullback = try {
            var source = expectedSource
            let native = try curveLaw(source, usage: &usage)
            let receipt = try OriginalSphereCurvePullback(sphere: sphere, curve: native,
                tolerance: tolerance, usage: &usage)
            source.controlPoints[0] = .init(x: 100, y: 100, z: 100)
            return receipt
        }()
        #expect(pullback.sphere == sphere && pullback.curve.source == expectedSource)
        #expect(pullback.curve.originalCurve == .bSpline(expectedSource))
        #expect(pullback.curve.spanIndex == 1 && pullback.curve.originalTranslation == 0)
        #expect(pullback.domain.lower == (try .originalDouble(2, usage: &usage)))
        #expect(pullback.domain.upper == (try .originalDouble(5, usage: &usage)))
        let t = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let linear = try t.scaled(by: .originalDouble(2, usage: &usage), usage: &usage)
            .subtracting(.constant(.originalDouble(6, usage: &usage), usage: &usage), usage: &usage)
        #expect(pullback.equation == (try linear.multiplied(by: linear, usage: &usage)))
        let station = try ExactRationalCoefficient.originalDouble(3, usage: &usage)
        let third = try ExactRationalCoefficient.one.divided(by: station, usage: &usage)
        let weight = try pullback.denominator.evaluated(atU: station, v: .zero, usage: &usage)
        #expect(weight == (try .one.adding(third, usage: &usage)))
        let result = try decompose(pullback, budget: budget)
        #expect(result.cells.count == 1)
        #expect(try result.contains(rationalPoint: [station], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
        #expect(try !result.contains(rationalPoint: [third], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func exactRationalCircleHasZeroRawEquationAndExplicitDenominatorGuard() throws {
        let budget = Budget(); var usage = budget.usage
        let native = try curveLaw(.init(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 1, y: 0, z: 0), .init(x: 1, y: 1, z: 0), .init(x: 0, y: 1, z: 0)],
            weights: [1, 1, 2]), usage: &usage)
        let pullback = try OriginalSphereCurvePullback(sphere: sphere, curve: native,
            tolerance: tolerance, usage: &usage)
        #expect(pullback.equation.isZero && pullback.denominator == native.homogeneous[3])
        let relation = try pullback.relation(usage: &usage)
        #expect(relation.polynomials.count == 2 && relation.domains == [pullback.domain])
        try RationalAlgebraStorage.retain(relation.predicate.original.maximumStackCount, of: Bool.self, usage: &usage)
        var scratch: [Bool] = []; scratch.reserveCapacity(relation.predicate.original.maximumStackCount)
        #expect(try relation.predicate.original.evaluate(signs: [.zero, .zero], scratch: &scratch, usage: &usage) == false)
        #expect(try relation.predicate.original.evaluate(signs: [.zero, .positive], scratch: &scratch, usage: &usage))
        let result = try decompose(pullback, budget: budget)
        #expect(result.components.count == 1 && result.components[0].dimension == 1)
        for station in [ExactRationalCoefficient.zero, .one] {
            #expect(try result.contains(rationalPoint: [station], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
        }
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &usage)
        #expect(try !result.contains(rationalPoint: [two], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func tinyStrictProximityKeepsNonzeroEquationAndWholeExclusion() throws {
        let budget = Budget(); var usage = budget.usage
        let delta = Double(sign: .plus, exponent: -40, significand: 1)
        let native = try curveLaw(.init(degree: 1, knots: [0, 0, 1, 1], controlPoints: [
            .init(x: -delta, y: 1 + delta, z: 0), .init(x: delta, y: 1 + delta, z: 0)]), usage: &usage)
        let pullback = try OriginalSphereCurvePullback(sphere: sphere, curve: native,
            tolerance: tolerance, usage: &usage)
        #expect(!pullback.equation.isZero)
        #expect(try pullback.equation.evaluated(atU: .zero, v: .zero, usage: &usage).isPositive)
        let result = try decompose(pullback, budget: budget)
        #expect(result.cells.isEmpty && result.components.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidSourceAndIndependentWorkStorageRejectReceiptAndAdapter() throws {
        let construction = Budget(); var originalUsage = construction.usage
        let native = try curveLaw(tangentSource(), usage: &originalUsage)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try OriginalSphereCurvePullback(sphere: .plane(origin: .origin, normal: .unitZ), curve: native,
                tolerance: tolerance, usage: &originalUsage)
        }
        #expect(throws: GeometryError.self) {
            try OriginalSphereCurvePullback(sphere: .sphere(center: .origin, radius: 0), curve: native,
                tolerance: tolerance, usage: &originalUsage)
        }
        var invalid = tangentSource(); invalid.weights[0] = 0
        #expect(throws: GeometryError.self) { try curveLaw(invalid, usage: &originalUsage) }
        let measured = Budget(); var successful = measured.usage
        let pullback = try OriginalSphereCurvePullback(sphere: sphere, curve: native,
            tolerance: tolerance, usage: &successful)
        #expect(measured.spent.cells == 0)
        let exact = Budget(work: measured.spent.work, storage: measured.spent.storage); var exactUsage = exact.usage
        #expect(try OriginalSphereCurvePullback(sphere: sphere, curve: native,
            tolerance: tolerance, usage: &exactUsage).equation == pullback.equation)
        for budget in [Budget(work: measured.spent.work - 1), Budget(storage: measured.spent.storage - 1)] {
            var usage = budget.usage
            geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
                try OriginalSphereCurvePullback(sphere: sphere, curve: native, tolerance: tolerance, usage: &usage)
            }
        }
        for budget in [Budget(work: 0), Budget(storage: 0)] {
            var usage = budget.usage
            geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { try pullback.relation(usage: &usage) }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func cancellationAtEntryAndFinalStorageCannotPublish(adapter: Bool) async throws {
        let construction = Budget(); var usage = construction.usage
        let native = try curveLaw(tangentSource(), usage: &usage)
        let pullback = try OriginalSphereCurvePullback(sphere: sphere, curve: native,
            tolerance: tolerance, usage: &usage)
        let measured = Budget(); var baseline = measured.usage
        if adapter { _ = try pullback.relation(usage: &baseline) }
        else { _ = try OriginalSphereCurvePullback(sphere: sphere, curve: native, tolerance: tolerance, usage: &baseline) }
        for atEntry in [false, true] {
            let budget = Budget(cancelAtStorageCall: atEntry ? nil : measured.spent.storageCalls)
            let cancelled = try await Task {
                if atEntry { withUnsafeCurrentTask { $0?.cancel() } }
                var operation = budget.usage
                do {
                    if adapter { _ = try pullback.relation(usage: &operation) }
                    else { _ = try OriginalSphereCurvePullback(sphere: sphere, curve: native,
                        tolerance: tolerance, usage: &operation) }
                    return false
                } catch where geometryTestIsCancelled(error) { return true }
            }.value
            #expect(cancelled)
            if atEntry { #expect(budget.spent.work == 0 && budget.spent.storage == 0) }
        }
    }
}
