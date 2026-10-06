import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite("Original direct analytic curve pullbacks")
struct OriginalAnalyticCurvePullbackTests {
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
        var usage: OriginalRelationUsage {
            .init(consumeWork: { count in
                try self.state.withLock { state in
                    guard count <= self.maximumWork - state.work else { throw Self.exhausted() }
                    state.work += count
                }
            }, retainStorage: { count in
                let cancel = try self.state.withLock { state in
                    guard count <= self.maximumStorage - state.storage else { throw Self.exhausted() }
                    state.storage += count; state.storageCalls += 1
                    return state.storageCalls == self.cancelAtStorageCall
                }
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }, visitCell: { depth in
                try self.state.withLock { state in
                    guard depth <= 24 else { throw Self.exhausted() }; state.cells += 1
                }
            }, visitCoefficientCell: { _ in
                Issue.record("Direct rational analytic preparation cannot invent coefficient roots.")
                throw Self.exhausted()
            })
        }
        private static func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Analytic source test exhausted independent caller admission.")
        }
    }

    private let tolerance = ModelingTolerance(distance: 1e-9, angle: 1e-9)
    private let resolver: any OriginalPolynomialRelationResolving = DefaultOriginalPolynomialRelationResolver()
    private var surfaces: [AnalyticSurface3D] { [
        .plane(origin: .origin, normal: .unitZ),
        .cylinder(origin: .origin, axis: .unitZ, radius: 1),
        .torus(center: .origin, axis: .unitZ, majorRadius: 2, minorRadius: 1)] }

    private func line(_ a: Point3D, _ b: Point3D, lower: Double = 0, upper: Double = 1,
        weights: [Double] = [1, 1]) -> BSplineCurve3D {
        .init(degree: 1, knots: [lower, lower, upper, upper], controlPoints: [a, b], weights: weights)
    }
    private func law(_ source: BSplineCurve3D, usage: inout OriginalRelationUsage)
        throws -> OriginalRationalCurvePolynomial {
        try .init(source: source, spanIndex: source.degree, tolerance: tolerance, usage: &usage)
    }
    private func receipt(_ surface: AnalyticSurface3D, _ source: BSplineCurve3D,
        usage: inout OriginalRelationUsage) throws -> OriginalAnalyticCurvePullback {
        try .init(surface: surface, curve: law(source, usage: &usage), tolerance: tolerance, usage: &usage)
    }
    private func decompose(_ pullback: OriginalAnalyticCurvePullback, usage: inout OriginalRelationUsage)
        throws -> OriginalRealRelation {
        try resolver.decompose(pullback.relation(usage: &usage), maximumDepth: 24,
            maximumCoefficientDepth: 0, usage: usage)
    }
    private func rational(_ numerator: Double, _ denominator: Double = 1,
        usage: inout OriginalRelationUsage) throws -> ExactRationalCoefficient {
        try .originalDouble(numerator, usage: &usage).divided(by: .originalDouble(denominator, usage: &usage), usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalPlaneNormalOriginAndClosedDomainRemainLiteral() throws {
        let budget = Budget(); var usage = budget.usage
        let normalZ = 1 + Double(sign: .plus, exponent: -40, significand: 1)
        let surface = AnalyticSurface3D.plane(origin: .init(x: 9, y: -3, z: 2),
            normal: .init(x: 0, y: 0, z: normalZ))
        let pullback = try receipt(surface, line(.init(x: 0, y: 0, z: 1),
            .init(x: 0, y: 0, z: 3), lower: -2, upper: 4), usage: &usage)
        let third = try rational(1, 3, usage: &usage)
        let linear = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .subtracting(.constant(.one, usage: &usage), usage: &usage).scaled(by: third, usage: &usage)
        let expected = try linear.scaled(by: .originalDouble(normalZ, usage: &usage), usage: &usage)
        #expect(pullback.equation == expected && pullback.equation != linear)
        #expect(pullback.originalFrame == nil && pullback.exactInverseFrame == nil)
        #expect(pullback.surface == surface && budget.spent.cells == 0)
        #expect(pullback.domain.lower == (try rational(-2, usage: &usage)))
        #expect(pullback.domain.upper == (try rational(4, usage: &usage)))
        let result = try decompose(pullback, usage: &usage)
        #expect(result.cells.count == 1 && result.components.count == 1)
        #expect(try result.contains(rationalPoint: [.one], maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage))
        #expect(try !result.contains(rationalPoint: [.zero], maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func cylinderRepeatedWeightedRootRetainsLawLifetimeAndDomain() throws {
        let budget = Budget(); var usage = budget.usage
        let expected = line(.init(x: -2, y: 1, z: -5), .init(x: 2, y: 1, z: 7),
            lower: 2, upper: 5, weights: [1, 2])
        let pullback = try { () throws -> OriginalAnalyticCurvePullback in
            var source = expected
            let issued = try receipt(surfaces[1], source, usage: &usage)
            source.controlPoints[0] = .init(x: 100, y: 100, z: 100)
            return issued
        }()
        let linear = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .scaled(by: rational(2, usage: &usage), usage: &usage)
            .subtracting(.constant(rational(6, usage: &usage), usage: &usage), usage: &usage)
        #expect(pullback.equation == (try linear.multiplied(by: linear, usage: &usage)))
        #expect(pullback.curve.source == expected && pullback.curve.originalCurve == .bSpline(expected))
        #expect(pullback.curve.spanIndex == 1 && pullback.curve.originalTranslation == 0)
        #expect(pullback.denominator == pullback.curve.homogeneous[3])
        #expect(pullback.domain.lower == (try rational(2, usage: &usage)))
        #expect(pullback.domain.upper == (try rational(5, usage: &usage)))
        #expect(budget.spent.cells == 0)
        let result = try decompose(pullback, usage: &usage)
        #expect(result.cells.count == 1 && result.cells[0].dimension == 0)
        #expect(try result.contains(rationalPoint: [rational(3, usage: &usage)],
            maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func torusQuarticKeepsFourOriginalPreimagesAndRepeatedTangency() throws {
        let budget = Budget(); var usage = budget.usage
        let pullback = try receipt(surfaces[2], line(.init(x: -4, y: 0, z: 0),
            .init(x: 4, y: 0, z: 0)), usage: &usage)
        let x = pullback.curve.homogeneous[0]
        let x2 = try x.multiplied(by: x, usage: &usage)
        let expected = try x2.subtracting(.constant(.one, usage: &usage), usage: &usage)
            .multiplied(by: x2.subtracting(.constant(rational(9, usage: &usage), usage: &usage), usage: &usage), usage: &usage)
        #expect(pullback.equation == expected && pullback.equation.uDegree == 4)
        let result = try decompose(pullback, usage: &usage)
        #expect(result.cells.count == 4 && result.components.count == 4)
        for numerator in [1.0, 3, 5, 7] {
            #expect(try result.contains(rationalPoint: [rational(numerator, 8, usage: &usage)],
                maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage))
        }
        #expect(try !result.contains(rationalPoint: [rational(1, 2, usage: &usage)],
            maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage))
        let tangent = try receipt(surfaces[2], line(.init(x: 1, y: 0, z: 1), .init(x: 3, y: 0, z: 1)), usage: &usage)
        let tx2 = try tangent.curve.homogeneous[0].multiplied(by: tangent.curve.homogeneous[0], usage: &usage)
            .subtracting(.constant(rational(4, usage: &usage), usage: &usage), usage: &usage)
        #expect(tangent.equation == (try tx2.multiplied(by: tx2, usage: &usage)))
        let roots = try decompose(tangent, usage: &usage)
        #expect(roots.cells.count == 1 && roots.components.count == 1)
        #expect(try roots.contains(rationalPoint: [rational(1, 2, usage: &usage)],
            maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2])
    func exactContainmentHasExplicitDenominatorGuard(family: Int) throws {
        let budget = Budget(); var usage = budget.usage
        let source: BSplineCurve3D
        if family == 0 { source = line(.origin, .init(x: 1, y: 0, z: 0)) }
        else {
            let controls: [Point3D] = family == 1
                ? [.init(x: 1, y: 0, z: 0), .init(x: 1, y: 1, z: 0), .init(x: 0, y: 1, z: 0)]
                : [.init(x: 3, y: 0, z: 0), .init(x: 3, y: 0, z: 1), .init(x: 2, y: 0, z: 1)]
            source = .init(degree: 2, knots: [0, 0, 0, 1, 1, 1], controlPoints: controls, weights: [1, 1, 2])
        }
        let pullback = try receipt(surfaces[family], source, usage: &usage)
        #expect(pullback.equation.isZero && pullback.denominator == pullback.curve.homogeneous[3])
        let relation = try pullback.relation(usage: &usage)
        #expect(relation.polynomials.count == 2 && relation.domains == [pullback.domain])
        try RationalAlgebraStorage.retain(relation.predicate.original.maximumStackCount, of: Bool.self, usage: &usage)
        var scratch: [Bool] = []; scratch.reserveCapacity(relation.predicate.original.maximumStackCount)
        #expect(try !relation.predicate.original.evaluate(signs: [.zero, .zero], scratch: &scratch, usage: &usage))
        #expect(try relation.predicate.original.evaluate(signs: [.zero, .positive], scratch: &scratch, usage: &usage))
        let result = try decompose(pullback, usage: &usage)
        #expect(result.components.count == 1 && result.components[0].dimension == 1)
        for station in [ExactRationalCoefficient.zero, .one] {
            #expect(try result.contains(rationalPoint: [station], maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage))
        }
        #expect(try !result.contains(rationalPoint: [rational(2, usage: &usage)], maximumDepth: 24,
            maximumCoefficientDepth: 0, usage: usage))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [1, 2])
    func originalNonunitFrameUsesExactInverseInsteadOfAxisProjection(family: Int) throws {
        let budget = Budget(); var usage = budget.usage
        let axisZ = 1 + Double(sign: .plus, exponent: -40, significand: 1)
        let axis = Vector3D(x: 0, y: 0, z: axisZ)
        let surface: AnalyticSurface3D = family == 1
            ? .cylinder(origin: .init(x: 4, y: -2, z: 3), axis: axis, radius: 1)
            : .torus(center: .init(x: 4, y: -2, z: 3), axis: axis, majorRadius: 2, minorRadius: 1)
        let point = family == 1 ? Point3D(x: 4, y: -1, z: 3 + axisZ)
            : Point3D(x: 4, y: 0, z: 3 + axisZ)
        let pullback = try receipt(surface, line(point, point), usage: &usage)
        #expect(pullback.equation.isZero)
        #expect(pullback.originalFrame?.basisZ == axis && pullback.exactInverseFrame?.count == 12)
        let inverseZ = try rational(1, usage: &usage).divided(by: .originalDouble(axisZ, usage: &usage), usage: &usage)
        #expect(pullback.exactInverseFrame?[10] == inverseZ)
        #expect(try decompose(pullback, usage: &usage).components[0].dimension == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func binaryChartBasisIsNotSilentlyMadeExactlyOrthonormal() throws {
        let budget = Budget(); var usage = budget.usage
        let axis = Vector3D(x: 0.6, y: 0.8, z: 0)
        let point = Point3D(x: -0.8, y: 0.6, z: 0)
        let pullback = try receipt(.cylinder(origin: .origin, axis: axis, radius: 1), line(point, point), usage: &usage)
        #expect(pullback.originalFrame?.basisY == .init(x: point.x, y: point.y, z: point.z))
        #expect(pullback.equation.isZero)
        let x = try ExactRationalCoefficient.originalDouble(point.x, usage: &usage)
        let y = try ExactRationalCoefficient.originalDouble(point.y, usage: &usage)
        let wrongUnitFrame = try x.multiplied(by: x, usage: &usage)
            .adding(y.multiplied(by: y, usage: &usage), usage: &usage).subtracting(.one, usage: &usage)
        #expect(!wrongUnitFrame.isZero)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2])
    func tinyProximityIsNonzeroAndExcludedOverWholeDomain(family: Int) throws {
        let budget = Budget(); var usage = budget.usage
        let delta = Double(sign: .plus, exponent: -40, significand: 1)
        let point: Point3D = family == 0 ? .init(x: 0, y: 0, z: delta)
            : family == 1 ? .init(x: 0, y: 1 + delta, z: 0) : .init(x: 2, y: 0, z: 1 + delta)
        let pullback = try receipt(surfaces[family], line(point, point), usage: &usage)
        #expect(!pullback.equation.isZero)
        #expect(try pullback.equation.evaluated(atU: .zero, v: .zero, usage: &usage).isPositive)
        let result = try decompose(pullback, usage: &usage)
        #expect(result.cells.isEmpty && result.components.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2])
    func periodicOriginalTranslationAndNativeSpanRemainBound(family: Int) throws {
        let budget = Budget(); var usage = budget.usage
        let source = try BSplineCurve3D.periodic(degree: 1, cycleKnots: [0, 1, 2, 3, 4],
            controlPoints: [.init(x: 1, y: 0, z: 0), .init(x: 0, y: 1, z: 0),
                .init(x: -1, y: 0, z: 0), .init(x: 0, y: -1, z: 0)], tolerance: tolerance)
        let native = try OriginalRationalCurvePolynomial(source: source, spanIndex: 1,
            originalTranslation: -8, tolerance: tolerance, usage: &usage)
        let pullback = try OriginalAnalyticCurvePullback(surface: surfaces[family], curve: native,
            tolerance: tolerance, usage: &usage)
        #expect(pullback.curve.source == source && pullback.curve.originalCurve == .bSpline(source))
        #expect(pullback.curve.originalTranslation == -8 && pullback.curve.spanIndex == 1)
        #expect(pullback.domain.lower == (try rational(-8, usage: &usage)))
        #expect(pullback.domain.upper == (try rational(-7, usage: &usage)))
        #expect(pullback.denominator == native.homogeneous[3])
        let unshifted = try receipt(surfaces[family], source, usage: &usage)
        #expect(try pullback.equation.evaluated(atU: rational(-15, 2, usage: &usage), v: .zero, usage: &usage)
            == unshifted.equation.evaluated(atU: rational(1, 2, usage: &usage), v: .zero, usage: &usage))
        #expect(try pullback.relation(usage: &usage).domains == [pullback.domain])
    }

    @Test(.timeLimit(.minutes(1)))
    func unsupportedAndInvalidOriginalSourcesRemainTyped() throws {
        let budget = Budget(); var usage = budget.usage
        let native = try law(line(.origin, .init(x: 1, y: 0, z: 0)), usage: &usage)
        do {
            _ = try OriginalAnalyticCurvePullback(surface: .cone(apex: .origin, axis: .unitZ, halfAngle: .pi / 4),
                curve: native, tolerance: tolerance, usage: &usage)
            Issue.record("Physical-radian cone slope must not become a rounded rational coefficient.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        #expect(throws: KernelError.self) {
            try OriginalAnalyticCurvePullback(surface: .sphere(center: .origin, radius: 1), curve: native,
                tolerance: tolerance, usage: &usage)
        }
        for surface in [AnalyticSurface3D.plane(origin: .origin, normal: .zero),
            .cylinder(origin: .origin, axis: .unitZ, radius: 0),
            .torus(center: .origin, axis: .unitZ, majorRadius: 1, minorRadius: 2)] {
            #expect(throws: GeometryError.self) {
                try OriginalAnalyticCurvePullback(surface: surface, curve: native, tolerance: tolerance, usage: &usage)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2])
    func callerWorkAndStorageIndependentlyAdmitPreparationAndAdapter(family: Int) throws {
        let construction = Budget(); var original = construction.usage
        let native = try law(line(.origin, .init(x: 1, y: 0, z: 0)), usage: &original)
        let measured = Budget(); var baseline = measured.usage
        let pullback = try OriginalAnalyticCurvePullback(surface: surfaces[family], curve: native,
            tolerance: tolerance, usage: &baseline)
        #expect(measured.spent.cells == 0)
        let exact = Budget(work: measured.spent.work, storage: measured.spent.storage); var exactUsage = exact.usage
        #expect(try OriginalAnalyticCurvePullback(surface: surfaces[family], curve: native,
            tolerance: tolerance, usage: &exactUsage).equation == pullback.equation)
        for budget in [Budget(work: measured.spent.work - 1), Budget(storage: measured.spent.storage - 1)] {
            var usage = budget.usage
            #expect(throws: KernelError.self) {
                try OriginalAnalyticCurvePullback(surface: surfaces[family], curve: native, tolerance: tolerance, usage: &usage)
            }
        }
        let adapter = Budget(); var adapterBaseline = adapter.usage
        _ = try pullback.relation(usage: &adapterBaseline)
        let exactAdapter = Budget(work: adapter.spent.work, storage: adapter.spent.storage); var exactAdapterUsage = exactAdapter.usage
        #expect(try pullback.relation(usage: &exactAdapterUsage).polynomials.count == 2)
        for budget in [Budget(work: adapter.spent.work - 1), Budget(storage: adapter.spent.storage - 1)] {
            var usage = budget.usage
            #expect(throws: KernelError.self) { try pullback.relation(usage: &usage) }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2])
    func cancellationAtEntryAndFinalAdmissionCannotPublish(family: Int) async throws {
        let construction = Budget(); var usage = construction.usage
        let native = try law(line(.origin, .init(x: 1, y: 0, z: 0)), usage: &usage)
        let surface = surfaces[family]
        let pullback = try OriginalAnalyticCurvePullback(surface: surface, curve: native, tolerance: tolerance, usage: &usage)
        for adapter in [false, true] {
            let measured = Budget(); var baseline = measured.usage
            if adapter { _ = try pullback.relation(usage: &baseline) }
            else { _ = try OriginalAnalyticCurvePullback(surface: surface, curve: native, tolerance: tolerance, usage: &baseline) }
            for atEntry in [false, true] {
                let budget = Budget(cancelAtStorageCall: atEntry ? nil : measured.spent.storageCalls)
                let cancelled = try await Task {
                    if atEntry { withUnsafeCurrentTask { $0?.cancel() } }
                    var operation = budget.usage
                    do {
                        if adapter { _ = try pullback.relation(usage: &operation) }
                        else { _ = try OriginalAnalyticCurvePullback(surface: surface, curve: native,
                            tolerance: tolerance, usage: &operation) }
                        return false
                    } catch is CancellationError { return true }
                }.value
                #expect(cancelled)
                if atEntry { #expect(budget.spent.work == 0 && budget.spent.storage == 0) }
            }
        }
    }
}
