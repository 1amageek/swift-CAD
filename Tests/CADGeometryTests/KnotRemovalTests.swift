import CADCore
import Foundation
@testable import CADGeometry
import Testing

@Suite("Certified immutable B-spline knot removal")
struct KnotRemovalTests {
    private let tolerance = ModelingTolerance.standard
    private let remover: any BSplineKnotRemoving = CertifiedBSplineKnotRemover()
    private let options = BSplineKnotRemovalOptions()

    private func open(rational: Bool = false, nonClamped: Bool = false) -> BSplineCurve3D {
        BSplineCurve3D(degree: 2,
            knots: nonClamped ? [-2, -1, 0, 1, 2, 3, 4] : [0, 0, 0, 1, 1, 1],
            controlPoints: nonClamped
                ? [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 2, z: 0),
                   .init(x: 2, y: 1, z: 1), .init(x: 3, y: 0, z: 0)]
                : [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 2, z: 1), .init(x: 3, y: 0, z: 0)],
            weights: rational ? (nonClamped ? [1, 2, 1.5, 0.75] : [1, 2, 0.75]) : nil)
    }

    private func periodic(degree: Int = 3, rational: Bool = false) throws -> BSplineCurve3D {
        try .periodic(degree: degree, cycleKnots: [3, 3.5, 5, 6, 8],
            controlPoints: [.init(x: 1, y: 0, z: 0), .init(x: 0, y: 2, z: 0.5),
                .init(x: -1, y: 0, z: 1), .init(x: 0, y: -2, z: 0.5)],
            weights: rational ? [1, 2, 0.5, 1.5] : nil, tolerance: tolerance)
            .changingPeriodicOrigin(to: 7.25, tolerance: tolerance)
    }

    private func reduce(_ curve: BSplineCurve3D, at knot: Double, to target: Int = 0,
        deviation: Double = 1e-7, limits: BSplineKnotRemovalOptions? = nil) throws -> BSplineKnotRemovalResult<BSplineCurve3D> {
        try remover.reducingMultiplicity(of: curve, at: knot, to: target,
            maximumDeviation: deviation, options: limits ?? options, tolerance: tolerance)
    }

    private func agree(_ source: BSplineCurve3D, _ result: BSplineCurve3D, parameters: [Double],
        bound: Double) throws {
        for parameter in parameters {
            let distance = try (source.point(at: parameter, tolerance: tolerance)
                - result.point(at: parameter, tolerance: tolerance)).length
            #expect(distance <= bound + 2e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func openRationalPolynomialAndNonClampedInverseRefinement() throws {
        for rational in [false, true] {
            for nonClamped in [false, true] {
                let base = open(rational: rational, nonClamped: nonClamped)
                let knot = nonClamped ? 0.375 : 0.25
                let source = try base.insertingKnot(knot, tolerance: tolerance)
                    .insertingKnot(knot, tolerance: tolerance)
                let snapshot = source
                let result = try reduce(source, at: knot)
                #expect(result.removedMultiplicity == 2)
                #expect(result.geometry.controlPointCount == base.controlPointCount)
                #expect(result.geometry.knots == base.knots)
                #expect(result.geometry.domain == source.domain)
                #expect(source == snapshot)
                #expect(result.certifiedMaximumDeviation <= 1e-7)
                let upper = nonClamped ? 2.0 : 1.0
                try agree(source, result.geometry,
                    parameters: (0...100).map { Double($0) * upper / 100 }, bound: result.certifiedMaximumDeviation)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rational2DUsesThePublicProtocolPath() throws {
        let base = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 0, y: 0), .init(x: 1, y: 2), .init(x: 3, y: 0)], weights: [1, 2, 0.75])
        let source = try base.insertingKnot(0.4, tolerance: tolerance)
        let result = try remover.reducingMultiplicity(of: source, at: 0.4, to: 0,
            maximumDeviation: 1e-7, options: options, tolerance: tolerance)
        #expect(result.geometry.knots == base.knots)
        for i in 0...50 {
            let parameter = Double(i) / 50
            let a = try source.point(at: parameter, tolerance: tolerance)
            let b = try result.geometry.point(at: parameter, tolerance: tolerance)
            #expect(hypot(a.x - b.x, a.y - b.y) <= result.certifiedMaximumDeviation + 2e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicInteriorSeamAndSmallCyclesRetainOriginsAndDomains() throws {
        for degree in [2, 3, 5] {
            for rational in [false, true] {
                let base = try periodic(degree: degree, rational: rational)
                for knot in [3.0, 4.25] {
                    let source = try base.insertingKnot(knot, tolerance: tolerance)
                    let target = knot == 3 ? 1 : 0
                    let result = try reduce(source, at: knot + 10, to: target)
                    #expect(result.geometry.isPeriodic)
                    #expect(result.geometry.periodicOrigin == 7.25)
                    #expect(result.geometry.domain == base.domain)
                    #expect(result.geometry.controlPointCount == base.controlPointCount)
                    try agree(source, result.geometry, parameters: (0...150).map { -7 + Double($0) * 0.1 },
                        bound: result.certifiedMaximumDeviation)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func removingLastSeamCopyRotatesTheBaseChartAndRetainsFunction() throws {
        // Constant cyclic geometry can lose any authored seam without changing its shape.
        let base = try BSplineCurve3D.periodic(degree: 3, cycleKnots: [3, 4, 5, 6, 8],
            controlPoints: Array(repeating: Point3D(x: 2, y: -1, z: 3), count: 4),
            weights: [1, 2, 3, 4], tolerance: tolerance)
            .changingPeriodicOrigin(to: -2.25, tolerance: tolerance)
        let result = try reduce(base, at: 8)
        #expect(result.geometry.knots[result.geometry.degree] == 4)
        #expect(result.geometry.periodicOrigin == base.periodicOrigin)
        #expect(result.geometry.domain == base.domain)
        #expect(result.geometry.controlPointCount == base.controlPointCount - 1)
        try agree(base, result.geometry, parameters: (0...100).map { -5 + Double($0) * 0.2 },
            bound: result.certifiedMaximumDeviation)
    }

    @Test(.timeLimit(.minutes(1)))
    func approximateRemovalIsCertifiedAgainstTheOriginalSource() throws {
        let base = open()
        var source = try base.insertingKnot(0.3, tolerance: tolerance)
            .insertingKnot(0.3, tolerance: tolerance)
        source.controlPoints[2].y += 2e-5
        let result = try reduce(source, at: 0.3, deviation: 1e-3)
        #expect(result.removedMultiplicity == 2)
        #expect(result.certifiedMaximumDeviation > 0)
        #expect(result.certifiedMaximumDeviation <= 1e-3)
        try agree(source, result.geometry, parameters: (0...200).map { Double($0) / 200 },
            bound: result.certifiedMaximumDeviation)
        #expect(throws: BSplineKnotRemovalError.self) { _ = try reduce(source, at: 0.3, deviation: 1e-10) }
    }

    @Test(.timeLimit(.minutes(1)))
    func sharpInteriorKnotIsRefusedWithoutChangingInput() throws {
        let source = BSplineCurve3D(degree: 1, knots: [0, 0, 0.5, 1, 1],
            controlPoints: [.init(x: 0, y: 0, z: 0), .init(x: 0.5, y: 2, z: 0), .init(x: 1, y: 0, z: 0)])
        let snapshot = source
        do {
            _ = try reduce(source, at: 0.5, deviation: 1e-6)
            Issue.record("A sharp corner cannot be certified at this tolerance.")
        } catch let error as BSplineKnotRemovalError {
            guard case .toleranceRejected(let bound, let requested) = error else {
                Issue.record("Expected tolerance refusal, received \(error)"); return
            }
            #expect(bound > requested)
        }
        #expect(source == snapshot)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidRequestsAndIndependentBudgetsAreTyped() throws {
        let source = try open(rational: true).insertingKnot(0.4, tolerance: tolerance)
        for knot in [0, 1, -1, .nan, 0.41] {
            do { _ = try reduce(source, at: knot); Issue.record("Expected invalid request.") }
            catch let error as BSplineKnotRemovalError {
                guard case .invalidInput = error else { Issue.record("Expected invalid input, received \(error)"); continue }
            }
        }
        for target in [-1, 1, 2] { #expect(throws: BSplineKnotRemovalError.self) { _ = try reduce(source, at: 0.4, to: target) } }
        for deviation in [-1.0, .infinity, .nan] {
            #expect(throws: BSplineKnotRemovalError.self) { _ = try reduce(source, at: 0.4, deviation: deviation) }
        }
        for limits in [BSplineKnotRemovalOptions(maximumGeneratedScalarCount: 1),
            BSplineKnotRemovalOptions(maximumWork: 1)] {
            #expect(throws: BSplineKnotRemovalError.resourceLimitExceeded) { _ = try reduce(source, at: 0.4, limits: limits) }
        }
        #expect(throws: BSplineKnotRemovalError.self) {
            _ = try reduce(source, at: 0.4, limits: .init(maximumWork: 0))
        }
        var malformed = source
        malformed.weights[0] = 0
        #expect(throws: BSplineKnotRemovalError.self) { _ = try reduce(malformed, at: 0.4) }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonpositiveReducedWeightsAndFiniteRangeFailureAreNumericalRefusals() throws {
        let source = BSplineCurve3D(degree: 1, knots: [0, 0, 0.5, 1, 1],
            controlPoints: [.init(x: 0, y: 0, z: 0), .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
            weights: [100, 1, 1])
        var overflow = source
        overflow.weights = [1, 1, 1]
        overflow.controlPoints[0].x = -1e308
        overflow.controlPoints[1].x = 1e308
        for curve in [source, overflow] {
            do { _ = try reduce(curve, at: 0.5, deviation: 1); Issue.record("Expected numerical failure.") }
            catch let error as BSplineKnotRemovalError {
                guard case .numericalFailure = error else { Issue.record("Expected numerical failure, received \(error)"); continue }
            }
        }
    }

    private func surface(periodicU: Bool, periodicV: Bool, rational: Bool) throws -> BSplineSurface3D {
        let uCount = periodicU ? 4 : 3
        let vCount = periodicV ? 4 : 3
        let controls = (0..<vCount).map { j in (0..<uCount).map { i in
            Point3D(x: Double(i), y: Double(j), z: Double(i * j) * 0.25)
        } }
        let weights = rational ? (0..<vCount).map { j in (0..<uCount).map { i in 1 + Double((i + j) % 3) * 0.25 } } : nil
        if periodicU || periodicV {
            var result = try BSplineSurface3D.periodic(uDegree: 2, vDegree: 2,
                uKnots: periodicU ? [3, 4, 5, 6, 8] : [0, 0, 0, 1, 1, 1],
                vKnots: periodicV ? [2, 3, 4, 5, 7] : [0, 0, 0, 1, 1, 1],
                controlPoints: controls, weights: weights, isUPeriodic: periodicU,
                isVPeriodic: periodicV, tolerance: tolerance)
            if periodicU { result = try result.changingPeriodicOrigin(direction: .u, to: 7.25, tolerance: tolerance) }
            if periodicV { result = try result.changingPeriodicOrigin(direction: .v, to: -2.5, tolerance: tolerance) }
            return result
        }
        return BSplineSurface3D(uDegree: 2, vDegree: 2, uKnots: [0, 0, 0, 1, 1, 1],
            vKnots: [0, 0, 0, 1, 1, 1], controlPoints: controls, weights: weights)
    }

    @Test(.timeLimit(.minutes(1)))
    func bothTensorAxesCoverOpenMixedAndDoublyPeriodicRationalSurfaces() throws {
        for uPeriodic in [false, true] {
            for vPeriodic in [false, true] {
                for rational in [false, true] {
                    let base = try surface(periodicU: uPeriodic, periodicV: vPeriodic, rational: rational)
                    for direction in [SurfaceParameterDirection.u, .v] {
                        let axisPeriodic = direction == .u ? uPeriodic : vPeriodic
                        let knot = axisPeriodic ? (direction == .u ? 3.5 : 2.5) : 0.375
                        let source = try base.insertingKnot(direction: direction, value: knot, tolerance: tolerance)
                        let snapshot = source
                        let result = try remover.reducingMultiplicity(of: source, direction: direction,
                            at: knot, to: 0, maximumDeviation: 1e-7, options: options, tolerance: tolerance)
                        #expect(result.geometry.uDomain == base.uDomain && result.geometry.vDomain == base.vDomain)
                        #expect(result.geometry.uPeriodicOrigin == base.uPeriodicOrigin)
                        #expect(result.geometry.vPeriodicOrigin == base.vPeriodicOrigin)
                        #expect(result.geometry.uKnots == base.uKnots && result.geometry.vKnots == base.vKnots)
                        #expect(source == snapshot)
                        for i in 0...8 {
                            for j in 0...8 {
                                let u = uPeriodic ? -2 + Double(i) * 1.25 : Double(i) / 8
                                let v = vPeriodic ? -3 + Double(j) * 1.25 : Double(j) / 8
                                let distance = try (source.point(u: u, v: v, tolerance: tolerance)
                                    - result.geometry.point(u: u, v: v, tolerance: tolerance)).length
                                #expect(distance <= result.certifiedMaximumDeviation + 2e-12)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceRefusalIsAtomicAndNetResourcesAreAdmitted() throws {
        let base = try surface(periodicU: false, periodicV: true, rational: true)
        var source = try base.insertingKnot(direction: .u, value: 0.25, tolerance: tolerance)
        let independentVCount = source.vControlPointCount - source.vDegree
        for row in source.controlPoints.indices where row % independentVCount == 1 {
            source.controlPoints[row][1].z += 0.1
        }
        try source.validate(tolerance: tolerance)
        let snapshot = source
        #expect(throws: BSplineKnotRemovalError.self) {
            _ = try remover.reducingMultiplicity(of: source, direction: .u, at: 0.25, to: 0,
                maximumDeviation: 1e-8, options: options, tolerance: tolerance)
        }
        #expect(source == snapshot)
        #expect(throws: BSplineKnotRemovalError.resourceLimitExceeded) {
            _ = try remover.reducingMultiplicity(of: source, direction: .u, at: 0.25, to: 0,
                maximumDeviation: 1, options: .init(maximumGeneratedScalarCount: 1), tolerance: tolerance)
        }
    }
}
