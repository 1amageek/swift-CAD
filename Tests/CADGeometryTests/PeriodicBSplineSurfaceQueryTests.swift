import CADCore
@testable import CADGeometry
import Testing

@Suite("Periodic tensor queries")
struct PeriodicBSplineSurfaceQueryTests {
    private let tolerance = ModelingTolerance.standard

    private func torus(degree: Int = 3, rational: Bool = true, doubleCover: Bool = false) throws -> BSplineSurface3D {
        let circle: [(Double, Double)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        let uCount = doubleCover ? 8 : 4
        let points = (0..<4).map { j in
            (0..<uCount).map { i in
                Point3D(x: (3 + circle[j].0) * circle[i % 4].0,
                    y: (3 + circle[j].0) * circle[i % 4].1, z: circle[j].1)
            }
        }
        let weights = (0..<4).map { j in
            (0..<uCount).map { i in rational ? 1 + Double(i % 4 + j) * 0.025 : 1 }
        }
        return try .periodic(uDegree: degree, vDegree: degree,
            uKnots: (0...uCount).map { 3 + Double($0) }, vKnots: [-2, -1, 0, 1, 2],
            controlPoints: points, weights: weights, isUPeriodic: true, isVPeriodic: true, tolerance: tolerance)
    }

    private func box(_ u0: Double, _ u1: Double, _ v0: Double, _ v1: Double) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u0, upper: u1),
            v: try ScalarInterval(lower: v0, upper: v1))
    }

    private func expectContains(_ enclosure: SurfaceDifferentialEnclosure,
                                _ jet: BSplineSurface3D.RationalDerivatives) {
        #expect(enclosure.position.contains(jet.position))
        #expect(enclosure.tangentU.contains(jet.tangentU))
        #expect(enclosure.tangentV.contains(jet.tangentV))
        #expect(enclosure.secondDerivativeUU.contains(jet.secondDerivativeUU))
        #expect(enclosure.secondDerivativeUV.contains(jet.secondDerivativeUV))
        #expect(enclosure.secondDerivativeVV.contains(jet.secondDerivativeVV))
    }

    @Test(.timeLimit(.minutes(1)))
    func inverseProjectionMergesBothSeamsAndReturnsChosenOrigins() throws {
        for rational in [false, true] {
            let source = try torus(rational: rational)
                .changingPeriodicOrigin(direction: .u, to: 5.25, tolerance: tolerance)
                .changingPeriodicOrigin(direction: .v, to: 1.25, tolerance: tolerance)
            for (u, v) in [(3.0, -2.0), (4.25, -0.75), (6.95, 1.75), (7.0, 2.0)] {
                let target = try source.point(u: u, v: v, tolerance: tolerance)
                let projected = try Surface3D.bSpline(source).parameterProjection(of: target, tolerance: tolerance)
                #expect(try abs(projected.u - source.normalizedParameter(u, direction: .u, tolerance: tolerance)) < 1e-7)
                #expect(try abs(projected.v - source.normalizedParameter(v, direction: .v, tolerance: tolerance)) < 1e-7)
                #expect(projected.u >= 5.25 && projected.u < 9.25 && projected.v >= 1.25 && projected.v < 5.25)
                #expect(projected.residual <= tolerance.distance)
                #expect((try source.point(u: projected.u, v: projected.v, tolerance: tolerance)
                    - projected.point).length == 0)
            }
            if case let .outsideTolerance(residual) = try Surface3D.bSpline(source).parameterProjectionResult(
                of: Point3D(x: 100, y: 100, z: 100), tolerance: tolerance) {
                #expect(residual > tolerance.distance)
            } else { Issue.record("A distant point returned a periodic surface root.") }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func genuineInteriorMultiplicityIsNotMergedAsASeam() throws {
        let source = try torus(rational: false, doubleCover: true)
        let target = try source.point(u: 3.25, v: -0.75, tolerance: tolerance)
        #expect((try source.point(u: 7.25, v: -0.75, tolerance: tolerance) - target).length < 1e-12)
        do {
            _ = try Surface3D.bSpline(source).parameterProjection(of: target, tolerance: tolerance)
            Issue.record("Distinct interior parameter roots were merged using spatial coincidence.")
        } catch let error as KernelError { #expect(error.code == .ambiguousSelection) }
    }

    @Test(.timeLimit(.minutes(1)))
    func shiftedSeamAndMultiCycleBoxesContainAllMixedJetsIncludingEndpoints() throws {
        for degree in [2, 3] {
            let source = try torus(degree: degree)
                .changingPeriodicOrigin(direction: .u, to: 5.25, tolerance: tolerance)
            let prepared = try PreparedSurfaceDifferentialEncloser(surface: .bSpline(source), tolerance: tolerance)
            for parameters in [try box(6.75, 7.25, 1.75, 2.25), try box(-9.2, -8.9, 5.1, 5.5),
                               try box(3, 11, -2, 6), try box(6.75, 7, -1.5, -1.25)] {
                let enclosure = try prepared.enclosure(over: parameters, tolerance: tolerance)
                #expect(try enclosure == DefaultSurfaceDifferentialEncloser().enclosure(
                    of: .bSpline(source), over: parameters, tolerance: tolerance))
                for j in 0...8 {
                    for i in 0...8 {
                        let u = parameters.u.lower + parameters.u.width * Double(i) / 8
                        let v = parameters.v.lower + parameters.v.width * Double(j) / 8
                        expectContains(enclosure, try source.surfaceDerivatives(u: u, v: v, tolerance: tolerance))
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preparedBoxesRemainIndependentAndClosestProjectionRetainsRepresentatives() throws {
        let source = try torus(rational: false)
            .changingPeriodicOrigin(direction: .u, to: 5.25, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .v, to: 1.25, tolerance: tolerance)
        let prepared = try PreparedSurfaceDifferentialEncloser(surface: .bSpline(source), tolerance: tolerance)
        let left = try box(3.5, 3.55, -1.5, -1.45), right = try box(5.5, 5.55, -1.5, -1.45)
        let a = try prepared.enclosure(over: left, tolerance: tolerance)
        let b = try prepared.enclosure(over: right, tolerance: tolerance)
        #expect(a.position.x.upper < b.position.x.lower)
        #expect(try prepared.enclosure(over: left, tolerance: tolerance) == a)
        let target = try source.point(u: 2, v: 2, tolerance: tolerance)
        let closest = try source.closestParameterProjection(of: target, tolerance: tolerance)
        #expect(closest.u == 6 && closest.v == 2 && closest.residual <= tolerance.distance)
        #expect((closest.point - target).length == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func cornerCrossingRequiresSubdivisionAtThePeriodicKnot() throws {
        let source = try torus(degree: 1, rational: false)
        let prepared = try PreparedSurfaceDifferentialEncloser(surface: .bSpline(source), tolerance: tolerance)
        do {
            _ = try prepared.enclosure(over: box(6.75, 7.25, -1.75, -1.25), tolerance: tolerance)
            Issue.record("A periodic C0 corner received a smooth derivative certificate.")
        } catch let error as KernelError { #expect(error.code == .singularGeometry) }
        let range = try box(6.75, 7, -1.75, -1.25)
        let enclosure = try prepared.enclosure(over: range, tolerance: tolerance)
        expectContains(enclosure, try source.surfaceDerivatives(u: 7, v: -1.5, tolerance: tolerance))
    }

    @Test(.timeLimit(.minutes(1)))
    func eitherSinglePeriodicAxisRetainsItsOpenCoordinateInQueries() throws {
        let circle: [(Double, Double)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        for uPeriodic in [false, true] {
            let points = uPeriodic ? (0..<2).map { j in
                circle.map { Point3D(x: $0.0, y: $0.1, z: Double(j)) }
            } : circle.map { entry in
                (0..<2).map { Point3D(x: entry.0, y: entry.1, z: Double($0)) }
            }
            let source = try BSplineSurface3D.periodic(uDegree: uPeriodic ? 3 : 1, vDegree: uPeriodic ? 1 : 3,
                uKnots: uPeriodic ? [3, 4, 5, 6, 7] : [0, 0, 1, 1],
                vKnots: uPeriodic ? [0, 0, 1, 1] : [3, 4, 5, 6, 7], controlPoints: points,
                isUPeriodic: uPeriodic, isVPeriodic: !uPeriodic, tolerance: tolerance)
                .changingPeriodicOrigin(direction: uPeriodic ? .u : .v, to: 5.25, tolerance: tolerance)
            let u = uPeriodic ? 4.25 : 0.4, v = uPeriodic ? 0.4 : 4.25
            let target = try source.point(u: u, v: v, tolerance: tolerance)
            let projection = try Surface3D.bSpline(source).parameterProjection(of: target, tolerance: tolerance)
            #expect(abs(projection.u - (uPeriodic ? 8.25 : 0.4)) < 1e-7)
            #expect(abs(projection.v - (uPeriodic ? 0.4 : 8.25)) < 1e-7)
            let range = try uPeriodic ? box(6.75, 7.25, 0.25, 0.75) : box(0.25, 0.75, 6.75, 7.25)
            let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(of: .bSpline(source), over: range, tolerance: tolerance)
            expectContains(enclosure, try source.surfaceDerivatives(u: uPeriodic ? 7 : 0.5,
                v: uPeriodic ? 0.5 : 7, tolerance: tolerance))
            if !uPeriodic {
                #expect(throws: KernelError.self) {
                    try DefaultSurfaceDifferentialEncloser().enclosure(of: .bSpline(source),
                        over: box(-0.1, 0.5, 6.75, 7.25), tolerance: tolerance)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func uniformNonunitPeriodicStripRetainsLiteralOpenAxisDerivatives(_ uPeriodic: Bool) throws {
        let circle: [(Double, Double)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        let points = uPeriodic ? (0..<2).map { j in
            circle.map { Point3D(x: $0.0, y: $0.1, z: Double(j)) }
        } : circle.map { entry in
            (0..<2).map { Point3D(x: entry.0, y: entry.1, z: Double($0)) }
        }
        let source = try BSplineSurface3D.periodic(uDegree: uPeriodic ? 3 : 1, vDegree: uPeriodic ? 1 : 3,
            uKnots: uPeriodic ? [3, 4, 5, 6, 7] : [0, 0, 1, 1],
            vKnots: uPeriodic ? [0, 0, 1, 1] : [3, 4, 5, 6, 7], controlPoints: points,
            weights: points.map { Array(repeating: 2.0, count: $0.count) },
            isUPeriodic: uPeriodic, isVPeriodic: !uPeriodic, tolerance: tolerance)
            .changingPeriodicOrigin(direction: uPeriodic ? .u : .v, to: 5.25, tolerance: tolerance)
        let u = uPeriodic ? 7.0 : 0.5, v = uPeriodic ? 0.5 : 7.0
        let point = try source.point(u: u, v: v, tolerance: tolerance)
        let jet = try source.surfaceDerivatives(u: u, v: v, tolerance: tolerance)
        // Uniform cubic basis values at the knot are 1/6, 2/3, 1/6.
        // The independent strip coordinate is exactly linear with unit tangent.
        let expected = Point3D(x: 0, y: 2.0 / 3, z: 0.5)
        #expect((point - expected).length <= Double.ulpOfOne * 8)
        #expect((jet.position - expected).length <= Double.ulpOfOne * 8)
        #expect((jet.position - point).length <= Double.ulpOfOne * 8)
        let openTangent = uPeriodic ? jet.tangentV : jet.tangentU
        let openSecond = uPeriodic ? jet.secondDerivativeVV : jet.secondDerivativeUU
        #expect((openTangent - Vector3D(x: 0, y: 0, z: 1)).length <= Double.ulpOfOne * 8)
        #expect(openSecond == .zero)
        let range = try uPeriodic ? box(6.75, 7.25, 0.25, 0.75) : box(0.25, 0.75, 6.75, 7.25)
        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(of: .bSpline(source), over: range, tolerance: tolerance)
        expectContains(enclosure, jet)
    }

    @Test(.timeLimit(.minutes(1)))
    func uniformOwningSpanDoesNotEraseUnequalEndpointWeights() throws {
        let source = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0.5, 1, 1],
            controlPoints: (0..<3).map { j in
                (0..<2).map { Point3D(x: Double($0), y: Double(j), z: 0) }
            }, weights: [[2, 2], [2, 2], [1, 4]])
        try source.validate(tolerance: tolerance)
        let polynomial = try source.surfaceDerivatives(u: 0.5, v: 0.25, tolerance: tolerance)
        #expect(polynomial.position == Point3D(x: 0.5, y: 0.5, z: 0))
        #expect(try source.point(u: 0.5, v: 0.25, tolerance: tolerance) == polynomial.position)
        #expect(polynomial.tangentV == Vector3D(x: 0, y: 2, z: 0))
        #expect(polynomial.secondDerivativeVV == .zero)
        // At the knot, the owning right span includes the zero-value basis
        // controls with unequal weights. Its native Y quotient is
        // (1 + 0 * h) / (1 - h), where h = v - 0.5.
        let rational = try source.surfaceDerivatives(u: 0, v: 0.5, tolerance: tolerance)
        #expect(rational.position == Point3D(x: 0, y: 1, z: 0))
        #expect(rational.tangentV.y == 1)
        #expect(rational.secondDerivativeVV.y == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCollapsedPeriodicAxisCannotProduceAnArbitraryUniqueRoot() throws {
        let source = try BSplineSurface3D.periodic(uDegree: 2, vDegree: 1,
            uKnots: [0, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin], [Point3D(x: 0, y: 0, z: 1)]],
            isUPeriodic: true, isVPeriodic: false, tolerance: tolerance)
        do {
            _ = try Surface3D.bSpline(source).parameterProjection(of: Point3D(x: 0, y: 0, z: 0.5),
                options: .init(maximumSubdivisionDepth: 0), tolerance: tolerance)
            Issue.record("A complete collapsed cycle was reported as one unique parameter root.")
        } catch let error as KernelError { #expect(error.code == .singularSystem) }
    }

    @Test(.timeLimit(.minutes(1)))
    func twoRegularRootsInsideOneBezierSpanCannotBeHiddenByAnExhaustedBudget() throws {
        let source = try BSplineSurface3D.periodic(uDegree: 2, vDegree: 1,
            uKnots: [0, 1, 3, 4], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, Point3D(x: 1, y: 0, z: 0), .origin],
                [Point3D(x: 0, y: 0, z: 1), Point3D(x: 1, y: 0, z: 1), Point3D(x: 0, y: 0, z: 1)]],
            isUPeriodic: true, isVPeriodic: false, tolerance: tolerance)
        let target = Point3D(x: 0.7, y: 0, z: 0.5)
        for u in [0.6 - Double(0.12).squareRoot(), 0.6 + Double(0.12).squareRoot()] {
            #expect((try source.point(u: u, v: 0.5, tolerance: tolerance) - target).length < 1e-12)
            _ = try source.normal(u: u, v: 0.5, tolerance: tolerance)
        }
        do {
            _ = try Surface3D.bSpline(source).parameterProjection(of: target,
                options: .init(maximumSubdivisionDepth: 0), tolerance: tolerance)
            Issue.record("One Newton witness hid a second regular root in the same Bezier span.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }

    @Test(.timeLimit(.minutes(1)))
    func exhaustedSearchAndUnrepresentableChosenRootsFailExplicitly() throws {
        let source = try torus()
        let target = try source.point(u: 4.25, v: -0.75, tolerance: tolerance)
        do {
            _ = try Surface3D.bSpline(source).parameterProjection(of: target,
                options: .init(maximumSubdivisionCells: 1), tolerance: tolerance)
            Issue.record("Periodic root search ignored its cell budget.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        let tight = ModelingTolerance(distance: 1e-10, angle: 1e-10, relative: 1e-12)
        let shifted = try source.changingPeriodicOrigin(direction: .u, to: 1e9, tolerance: tight)
        let fractionalTarget = try source.point(u: 4.1234567, v: -0.7654321, tolerance: tight)
        do {
            _ = try Surface3D.bSpline(shifted).parameterProjection(of: fractionalTarget, tolerance: tight)
            Issue.record("A rounded large-origin representative changed the projected point silently.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }
}
