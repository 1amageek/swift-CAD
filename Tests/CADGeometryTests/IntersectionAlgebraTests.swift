import CADCore
@testable import CADGeometry
import Testing

@Suite("Original Intersection Algebra")
struct IntersectionAlgebraTests {
    private typealias Polynomial = ExactIntersectionPolynomial

    private struct Admission: RationalAlgebraAdmitting {
        var work = 0
        var storage = 0
        var maximumWork = 10_000_000
        var maximumStorage = 10_000_000
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw exhausted() }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw exhausted() }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            throw rationalAlgebraFailure("Exact ideal preparation must not invent geometric root cells.")
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            throw rationalAlgebraFailure("Rational ideal preparation must not invent coefficient extensions.")
        }
        private func exhausted() -> KernelError {
            KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original test caller exhausted its independent allowance.")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func finiteThreeVariableEliminationPreservesOriginalEquations() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let a = try x.multiplied(by: x, usage: &usage).subtracting(one, usage: &usage)
        let b = try y.subtracting(x, usage: &usage)
        let c = try z.subtracting(y, usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: [a, b, c], variableCount: 3, usage: &usage)
        #expect(ideal.classification == .zeroDimensional)
        #expect(ideal.reducedBasis == [a, b, try z.subtracting(x, usage: &usage)])
        for value in [ExactRationalCoefficient.one, .one.negated] {
            for equation in ideal.originalEquations {
                #expect(try equation.evaluated(at: [value, value, value], usage: &usage).isZero)
            }
        }
        #expect(try a.evaluated(at: [.zero, .zero, .zero], usage: &usage) == .one.negated)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearSPairsProduceDeterministicReducedBasis() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let a = try y.multiplied(by: x, usage: &usage).subtracting(one, usage: &usage)
        let b = try y.subtracting(x, usage: &usage)
        let redundant = try a.adding(b, usage: &usage)
        let first = try ExactIntersectionIdeal.prepare(equations: [a, b, z, redundant, b],
            variableCount: 3, usage: &usage)
        let second = try ExactIntersectionIdeal.prepare(equations: [z, redundant, b, a],
            variableCount: 3, usage: &usage)
        #expect(first.classification == .zeroDimensional)
        #expect(first.reducedBasis == second.reducedBasis)
        let xSquaredMinusOne = try x.multiplied(by: x, usage: &usage).subtracting(one, usage: &usage)
        #expect(first.reducedBasis == [xSquaredMinusOne, b, z])
    }

    @Test(.timeLimit(.minutes(1)))
    func complexDimensionDoesNotClaimRealCurveOrAbsence() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let sumOfSquares = try x.multiplied(by: x, usage: &usage)
            .adding(y.multiplied(by: y, usage: &usage), usage: &usage)
        // Its real locus is one point while the complex ideal has positive dimension.
        let isolatedRealPoint = try ExactIntersectionIdeal.prepare(equations: [sumOfSquares, z],
            variableCount: 3, usage: &usage)
        #expect(isolatedRealPoint.classification == .positiveDimensional)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let noRealPoint = try ExactIntersectionIdeal.prepare(
            equations: [sumOfSquares.adding(one, usage: &usage), z], variableCount: 3, usage: &usage)
        #expect(noRealPoint.classification == .positiveDimensional)
    }

    @Test(.timeLimit(.minutes(1)))
    func denominatorSaturationExcludesAnExtraneousZero() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 4, at: 0, usage: &usage)
        let inverse = try Polynomial.coordinate(variableCount: 4, at: 3, usage: &usage)
        let one = try Polynomial.constant(variableCount: 4, value: .one, usage: &usage)
        let guardEquation = try x.multiplied(by: inverse, usage: &usage).subtracting(one, usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: [x, guardEquation],
            variableCount: 4, usage: &usage)
        #expect(ideal.classification == .inconsistent)
        #expect(ideal.reducedBasis == [one])
    }

    @Test(.timeLimit(.minutes(1)))
    func originalWeightedCurveAndNonunitSurfaceChartKeepTheirParameters() throws {
        var usage = Admission()
        let surface = horizontalSurface()
        let law = try surfaceLaw(surface, usage: &usage)
        let curve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0.5, y: 0.5, z: -1), Point3D(x: 0.5, y: 0.5, z: 1)],
            weights: [1, 2])
        let curveLaw = try OriginalRationalCurvePolynomial(source: curve, spanIndex: 1,
            tolerance: .standard, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(curve: curveLaw, surface: law, usage: &usage)
        let third = try ExactRationalCoefficient.one.divided(by: .natural(3, usage: &usage), usage: &usage)
        let u = try ExactRationalCoefficient.natural(3, usage: &usage)
        let v = try ExactRationalCoefficient.natural(7, usage: &usage)
        for equation in system.equations {
            #expect(try equation.evaluated(at: [third, u, v], usage: &usage).isZero)
        }
        let half = try ExactRationalCoefficient.one.divided(by: .natural(2, usage: &usage), usage: &usage)
        #expect(try !system.equations[2].evaluated(at: [half, u, v], usage: &usage).isZero)
        #expect(try !system.equations[0].evaluated(at: [third, half, half], usage: &usage).isZero)
        #expect(system.curveSource?.source == curve)
        #expect(system.firstSurfaceSource.domain == law.domain)
        #expect(try system.saturatedIdeal(usage: &usage).classification == .zeroDimensional)
    }

    @Test(.timeLimit(.minutes(1)))
    func fourVariableOriginalSurfaceSystemRetainsBothSourceCharts() throws {
        var usage = Admission()
        let first = try surfaceLaw(horizontalSurface(), usage: &usage)
        let vertical = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [2, 2, 4, 4], vKnots: [5, 5, 9, 9],
            controlPoints: [[Point3D(x: 0, y: 0.5, z: -1), Point3D(x: 1, y: 0.5, z: -1)],
                            [Point3D(x: 0, y: 0.5, z: 1), Point3D(x: 1, y: 0.5, z: 1)]])
        let second = try surfaceLaw(vertical, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(first: first, second: second, usage: &usage)
        let three = try ExactRationalCoefficient.natural(3, usage: &usage)
        let seven = try ExactRationalCoefficient.natural(7, usage: &usage)
        for equation in system.equations {
            #expect(try equation.evaluated(at: [three, seven, three, seven], usage: &usage).isZero)
        }
        #expect(system.firstSurfaceSource.source == first.source)
        #expect(system.secondSurfaceSource?.source == second.source)
        #expect(try system.saturatedIdeal(usage: &usage).classification == .positiveDimensional)
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceBitsFractionsDerivativesAndRingChecksRemainExact() throws {
        var usage = Admission()
        let original = try ExactRationalCoefficient.originalDouble(0.1, usage: &usage)
        let term = try Polynomial.monomial(variableCount: 4, powers: (1, 2, 0, 3, 0),
            coefficient: original, usage: &usage)
        let derivative = try term.differentiated(at: 3, usage: &usage)
        let expected = try original.multiplied(by: .natural(3, usage: &usage), usage: &usage)
        #expect(try derivative.evaluated(at: [.one, .one, .one, .one], usage: &usage) == expected)
        #expect(throws: KernelError.self) {
            try Polynomial.monomial(variableCount: 3, powers: (0, 0, 0, 1, 0),
                coefficient: .one, usage: &usage)
        }
        let other = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        #expect(throws: KernelError.self) { try term.adding(other, usage: &usage) }
        let maximum = try Polynomial.monomial(variableCount: 4, powers: (Int.max, 0, 0, 0, 0),
            coefficient: .one, usage: &usage)
        let x = try Polynomial.coordinate(variableCount: 4, at: 0, usage: &usage)
        #expect(throws: KernelError.self) { try maximum.multiplied(by: x, usage: &usage) }
    }

    @Test(.timeLimit(.minutes(1)))
    func workAndStorageFailureDoNotPublishAPartialIdeal() throws {
        var preparation = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &preparation)
        var exhaustedWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) {
            try ExactIntersectionIdeal.prepare(equations: [x], variableCount: 3, usage: &exhaustedWork)
        }
        #expect(exhaustedWork.storage == 0)
        var exhaustedStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) {
            try ExactIntersectionIdeal.prepare(equations: [x], variableCount: 3, usage: &exhaustedStorage)
        }
        #expect(exhaustedStorage.work > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledPreparationFailsBeforeConsumingCallerAllowance() async throws {
        var preparation = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &preparation)
        let stopped = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var usage = Admission()
            do {
                _ = try ExactIntersectionIdeal.prepare(equations: [x], variableCount: 3, usage: &usage)
                return false
            } catch is CancellationError {
                return usage.work == 0 && usage.storage == 0
            } catch { return false }
        }.value
        #expect(stopped)
    }

    @Test(.timeLimit(.minutes(1)))
    func canonicalRationalHashUsesSourceValueRatherThanRoundedRepresentatives() throws {
        var usage = Admission()
        let half = try ExactRationalCoefficient.one.divided(by: .natural(2, usage: &usage), usage: &usage)
        let same = try ExactRationalCoefficient.originalDouble(0.5, usage: &usage)
        let distinct = try ExactRationalCoefficient.originalDouble(0.5.nextUp, usage: &usage)
        #expect(Set([half, same, distinct]).count == 2)
        #expect(half.hashValue == same.hashValue)
        #expect(OriginalAngularParameterTransport.physicalRadians(gain: half, offset: .zero)
            == .physicalRadians(gain: same, offset: .zero))
    }

    @Test(.timeLimit(.minutes(1)))
    func nearParallelNativePlanesHaveNoOriginalCommonPoint() throws {
        var usage = Admission()
        let source = horizontalSurface()
        let first = try surfaceLaw(source, usage: &usage)
        let near = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: source.uKnots, vKnots: source.vKnots,
            controlPoints: [[Point3D(x: 0, y: 0, z: 5e-7), Point3D(x: 1, y: 0, z: 5e-7)],
                            [Point3D(x: 0, y: 1, z: 5e-7), Point3D(x: 1, y: 1, z: 5e-7)]])
        let second = try surfaceLaw(near, usage: &usage)
        let separated = try OriginalRationalIntersectionSystem(first: first, second: second, usage: &usage)
        #expect(try separated.saturatedIdeal(usage: &usage).classification == .inconsistent)
        let equal = try OriginalRationalIntersectionSystem(first: first, second: first, usage: &usage)
        // Independent UV coordinates remain related even for the same image source.
        #expect(try equal.saturatedIdeal(usage: &usage).classification == .positiveDimensional)
        for equation in equal.equations {
            #expect(try equation.evaluated(at: [.natural(3, usage: &usage), .natural(7, usage: &usage),
                .natural(3, usage: &usage), .natural(7, usage: &usage)], usage: &usage).isZero)
        }
    }

    private func horizontalSurface() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [2, 2, 4, 4], vKnots: [5, 5, 9, 9],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]])
    }

    private func surfaceLaw(_ surface: BSplineSurface3D, usage: inout Admission)
        throws -> OriginalRationalSurfacePolynomial {
        let domain = SurfaceParameterBox(u: try ScalarInterval(lower: 2, upper: 4),
                                         v: try ScalarInterval(lower: 5, upper: 9))
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        let native = try #require(prepared.originalNativeSpans(over: domain, tolerance: .standard).first)
        return try OriginalRationalSurfacePolynomial(source: surface, native: native,
            domain: domain, view: Vector3D(x: 0, y: 0, z: 1), tolerance: .standard, usage: &usage)
    }
}
