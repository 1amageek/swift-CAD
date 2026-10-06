import CADCore
@testable import CADGeometry
import Testing

@Suite("Finite original intersection fibers")
struct FiniteIntersectionFiberTests {
    private typealias Polynomial = ExactIntersectionPolynomial
    private struct Admission: RationalAlgebraAdmitting {
        var work = 0, storage = 0, cells = 0
        var maximumWork = 10_000_000, maximumStorage = 10_000_000
        var maximumDepth = 24, maximumCells = 100_000
        var cancelAtFirstRootVisit = false
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw exhausted("work=\(work), storage=\(storage), cells=\(cells)") }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw exhausted("storage=\(storage), work=\(work), cells=\(cells)") }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumDepth, cells < maximumCells else { throw exhausted() }
            cells += 1
            if cancelAtFirstRootVisit { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            throw rationalAlgebraFailure("Rational finite lifting cannot invent coefficient roots.")
        }
        private func exhausted(_ detail: String = "root admission") -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                  message: "Finite test caller exhausted its independent admission: \(detail).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func irrationalTowerEnumeratesEveryRealLiftAndKeepsOriginalCoordinates() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let two = try Polynomial.constant(variableCount: 2, value: .natural(2, usage: &usage), usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: [
            x.multiplied(by: x, usage: &usage).subtracting(two, usage: &usage),
            y.multiplied(by: y, usage: &usage).subtracting(x, usage: &usage)],
            variableCount: 2, usage: &usage)
        let fiber = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        // x = -sqrt(2) has no real y; x = sqrt(2) has two fourth-root lifts.
        #expect(fiber.points.count == 2)
        var negative = 0, positive = 0
        for point in fiber.points {
            #expect(point.coordinates.allSatisfy { $0.context === point.context })
            let a = point.coordinates[0], b = point.coordinates[1]
            #expect(try a.sign(maximumDepth: 24, usage: &usage) == .positive)
            let square = try b.multiplied(by: b, maximumDepth: 24, usage: &usage)
            #expect(try square.subtracting(a, maximumDepth: 24, usage: &usage)
                .sign(maximumDepth: 24, usage: &usage) == .zero)
            switch try b.sign(maximumDepth: 24, usage: &usage) {
            case .negative: negative += 1
            case .positive: positive += 1
            case .zero: Issue.record("A fourth root of two cannot be zero.")
            }
        }
        #expect(negative == 1 && positive == 1)
        #expect(usage.cells > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedRootsAndClosedEndpointRestrictionsAreExact() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let one = try Polynomial.constant(variableCount: 1, value: .one, usage: &usage)
        let pair = try x.multiplied(by: x, usage: &usage).subtracting(one, usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: [pair.multiplied(by: pair, usage: &usage)],
            variableCount: 1, usage: &usage)
        let all = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
            domains: [nil], maximumDepth: 24, usage: &usage)
        #expect(all.points.count == 2)
        let endpoint = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
            domains: [try .init(lower: 1, upper: 1)], maximumDepth: 24, usage: &usage)
        #expect(endpoint.points.count == 1)
        let excluded = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
            domains: [try .init(lower: Double(1).nextUp, upper: 2)], maximumDepth: 24, usage: &usage)
        #expect(excluded.points.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func complexOnlyFiniteFiberIsEmptyButPositiveDimensionIsRejected() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let one = try Polynomial.constant(variableCount: 1, value: .one, usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: [
            x.multiplied(by: x, usage: &usage).adding(one, usage: &usage)],
            variableCount: 1, usage: &usage)
        let fiber = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
            domains: [nil], maximumDepth: 24, usage: &usage)
        #expect(fiber.points.isEmpty)
        let impossible = try ExactIntersectionIdeal.prepare(equations: [one], variableCount: 1, usage: &usage)
        #expect(try OriginalFiniteIntersectionFiber.prepare(ideal: impossible,
            domains: [nil], maximumDepth: 24, usage: &usage).points.isEmpty)
        #expect(throws: KernelError.self) {
            _ = try OriginalFiniteIntersectionFiber.prepare(ideal: impossible,
                domains: [], maximumDepth: 24, usage: &usage)
        }
        let positive = try ExactIntersectionIdeal.prepare(equations: [], variableCount: 1, usage: &usage)
        do {
            _ = try OriginalFiniteIntersectionFiber.prepare(ideal: positive,
                domains: [nil], maximumDepth: 24, usage: &usage)
            Issue.record("Positive complex dimension requires its own real decomposition.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
    }

    @Test(.timeLimit(.minutes(1)))
    func rootAdmissionAndLedgerFailuresCannotPublishPartialTuples() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let one = try Polynomial.constant(variableCount: 1, value: .one, usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: [
            x.multiplied(by: x, usage: &usage).subtracting(one, usage: &usage)],
            variableCount: 1, usage: &usage)
        var depth = usage; depth.maximumDepth = 0
        #expect(throws: KernelError.self) {
            _ = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
                domains: [nil], maximumDepth: 0, usage: &depth)
        }
        #expect(depth.work > usage.work)
        var storage = usage; storage.maximumStorage = storage.storage
        #expect(throws: KernelError.self) {
            _ = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
                domains: [nil], maximumDepth: 24, usage: &storage)
        }
        #expect(storage.work > usage.work)
        var work = usage; work.maximumWork = work.work
        #expect(throws: KernelError.self) {
            _ = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
                domains: [nil], maximumDepth: 24, usage: &work)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringRootLiftingRestoresTheSameChargedLedger() async throws {
        let result = try await Task { () throws -> Int in
            var usage = Admission()
            let x = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
            let ideal = try ExactIntersectionIdeal.prepare(equations: [x], variableCount: 1, usage: &usage)
            usage.cancelAtFirstRootVisit = true
            do {
                _ = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
                    domains: [nil], maximumDepth: 24, usage: &usage)
                Issue.record("Cancellation during the root issuer cannot publish a finite fiber.")
            } catch is CancellationError { return usage.cells }
            return -1
        }.value
        #expect(result == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func saturatedNativeCurveSurfaceFiberPreservesAllAuthoredParameters() throws {
        var usage = Admission()
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [2, 2, 4, 4], vKnots: [5, 5, 9, 9],
            controlPoints: [[.origin, .init(x: 1, y: 0, z: 0)],
                            [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let box = SurfaceParameterBox(u: try .init(lower: 2, upper: 4),
                                      v: try .init(lower: 5, upper: 9))
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        let native = try #require(prepared.originalNativeSpans(over: box, tolerance: .standard).first)
        let surfaceLaw = try OriginalRationalSurfacePolynomial(source: surface, native: native,
            domain: box, view: .unitZ, tolerance: .standard, usage: &usage)
        let curve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.init(x: 0.5, y: 0.5, z: -1), .init(x: 0.5, y: 0.5, z: 1)], weights: [1, 2])
        let curveLaw = try OriginalRationalCurvePolynomial(source: curve, spanIndex: 1,
            tolerance: .standard, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(curve: curveLaw, surface: surfaceLaw, usage: &usage)
        let ideal = try system.saturatedIdeal(usage: &usage)
        let fiber = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
            domains: [try .init(lower: 0, upper: 1), box.u, box.v, nil], maximumDepth: 24, usage: &usage)
        let point = try #require(fiber.points.first)
        #expect(fiber.points.count == 1)
        #expect(point.coordinateRoots.count == 4)
        #expect(point.context.parent == nil)
        let expected: [ExactRationalCoefficient] = [
            try .one.divided(by: .natural(3, usage: &usage), usage: &usage),
            try .natural(3, usage: &usage), try .natural(7, usage: &usage)]
        for axis in 0..<3 {
            let exact = try OriginalSingularFieldElement.constant(expected[axis], in: point.context,
                maximumDepth: 24, usage: &usage)
            #expect(try point.coordinates[axis].subtracting(exact, maximumDepth: 24, usage: &usage)
                .sign(maximumDepth: 24, usage: &usage) == .zero)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func fieldReductionBoundsDegreeAndPreservesEqualityWithoutZeroDenominatorCancellation() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let two = try Polynomial.constant(variableCount: 1, value: .natural(2, usage: &usage), usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: [
            x.multiplied(by: x, usage: &usage).subtracting(two, usage: &usage)],
            variableCount: 1, usage: &usage)
        let fiber = try OriginalFiniteIntersectionFiber.prepare(ideal: ideal,
            domains: [nil], maximumDepth: 24, usage: &usage)
        let point = try #require(fiber.points.first)
        var power = point.coordinates[0]
        for _ in 0..<6 {
            power = try power.multiplied(by: power, maximumDepth: 24, usage: &usage)
            guard case .extended(let numerator, let denominator) = power.storage else {
                Issue.record("Reduction must retain the original extension field owner."); return
            }
            #expect(numerator.degree < 2 && denominator.degree < 2)
        }
        let expected = try OriginalSingularFieldElement.constant(.originalDouble(4_294_967_296, usage: &usage),
            in: point.context, maximumDepth: 24, usage: &usage)
        #expect(try power.subtracting(expected, maximumDepth: 24, usage: &usage)
            .sign(maximumDepth: 24, usage: &usage) == .zero)
        let zero = try power.subtracting(power, maximumDepth: 24, usage: &usage)
        #expect(throws: KernelError.self) { _ = try power.divided(by: zero, maximumDepth: 24, usage: &usage) }
        guard case .extended(let root) = point.context.source else {
            Issue.record("The lifted station must retain its original root."); return
        }
        let invalid = OriginalSingularFieldElement(context: point.context,
            storage: .extended(root.polynomial, root.polynomial))
        #expect(throws: KernelError.self) {
            _ = try invalid.multiplied(by: power, maximumDepth: 24, usage: &usage)
        }
        let rational = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        let wrongStorage = OriginalSingularFieldElement(context: point.context, storage: .original(rational, rational))
        #expect(throws: KernelError.self) {
            _ = try wrongStorage.sign(maximumDepth: 24, usage: &usage)
        }
    }
}
