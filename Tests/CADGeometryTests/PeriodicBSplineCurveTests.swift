import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Periodic B-spline curve values")
struct PeriodicBSplineCurveTests {
    private let tolerance = ModelingTolerance.standard

    private func curve(rational: Bool = false) throws -> BSplineCurve3D {
        try .periodic(
            degree: 3, cycleKnots: [3, 3.5, 5, 6, 8],
            controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 2, z: 0.5),
                Point3D(x: -1, y: 0, z: 1), Point3D(x: 0, y: -2, z: 0.5)],
            weights: rational ? [1, 2, 0.5, 1.5] : nil, tolerance: tolerance
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicValuesMatchTheIndependentUnwrappedBasisAcrossCycles() throws {
        for rational in [false, true] {
            let cyclic = try curve(rational: rational)
            let prepared = try ValidatedCurve3D(.bSpline(cyclic), tolerance: tolerance)
            #expect(prepared.parameterDomain == .periodic(period: 5))
            for index in 0..<41 {
                let parameter = 3 + (Double(index) + 0.25) * 5 / 41
                let basis = BSplineBasis.values(parameter: parameter, degree: cyclic.degree,
                    knots: cyclic.knots, count: cyclic.controlPointCount)
                var numerator = Vector3D.zero
                var denominator = 0.0
                for (i, value) in basis.enumerated() {
                    let coefficient = value * cyclic.weights[i]
                    numerator = numerator + Vector3D(x: cyclic.controlPoints[i].x,
                        y: cyclic.controlPoints[i].y, z: cyclic.controlPoints[i].z) * coefficient
                    denominator += coefficient
                }
                let expected = Point3D.origin + numerator / denominator
                for cycle in -3...3 {
                    let actual = try prepared.point(at: parameter + Double(cycle) * 5)
                    #expect((actual - expected).length < 1e-12)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func translatedKnotsAndControlsEstablishSeamDerivativeContinuity() throws {
        for rational in [false, true] {
            let cyclic = try curve(rational: rational)
            #expect(cyclic.periodicSeamContinuityOrder == 2)
            let unwrapped = BSplineCurve3D(degree: cyclic.degree, knots: cyclic.knots,
                controlPoints: cyclic.controlPoints, weights: cyclic.weights)
            let left = try unwrapped.parameterDerivatives(at: 8, tolerance: tolerance)
            let right = try unwrapped.parameterDerivatives(at: 3, tolerance: tolerance)
            #expect((left.position - right.position).length < 1e-12)
            #expect((left.firstDerivative - right.firstDerivative).length < 1e-12)
            #expect((left.secondDerivative - right.secondDerivative).length < 1e-12)
            for parameter in [3.0, 3.25, 4.0, 5.5, 7.75, 8.0] {
                let expected = try cyclic.parameterDerivatives(at: parameter, tolerance: tolerance)
                let actual = try cyclic.parameterDerivatives(at: parameter - 10, tolerance: tolerance)
                #expect((actual.position - expected.position).length < 1e-12)
                #expect((actual.firstDerivative - expected.firstDerivative).length < 1e-12)
                #expect((actual.secondDerivative - expected.secondDerivative).length < 1e-12)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func changingTheFundamentalOriginPreservesTheCurveFunction() throws {
        let original = try curve(rational: true)
        let moved = try original.changingPeriodicOrigin(to: 7.25, tolerance: tolerance)
        #expect(moved.fundamentalDomain == .closed(7.25, 12.25))
        for parameter in [-12.5, 0, 3, 7.25, 8, 12.25, 26] {
            let normalized = try moved.normalizedParameter(parameter, tolerance: tolerance)
            #expect(normalized >= 7.25 && normalized < 12.25)
            #expect((try moved.point(at: normalized, tolerance: tolerance)
                - original.point(at: parameter, tolerance: tolerance)).length < 1e-12)
            #expect(try moved.parameterDerivatives(at: parameter, tolerance: tolerance)
                == original.parameterDerivatives(at: parameter, tolerance: tolerance))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aLargeOriginDoesNotReplaceTheKnotPeriodWithRoundedIntervalWidth() throws {
        let cyclic = try BSplineCurve3D.periodic(degree: 3, cycleKnots: [0, 0.25, 0.55, 0.85, 1.1],
            controlPoints: [.origin, Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 0, z: 0),
                Point3D(x: 1, y: -1, z: 0)], tolerance: tolerance)
        let origin = 100_000_000.0
        let shifted = try cyclic.changingPeriodicOrigin(to: origin, tolerance: tolerance)
        let parameter = origin + 1_100_000.3
        let expected = origin + (parameter - origin).truncatingRemainder(dividingBy: 1.1)
        #expect(try shifted.normalizedParameter(parameter, tolerance: tolerance) == expected)
        #expect(try shifted.point(at: parameter, tolerance: tolerance) == cyclic.point(at: parameter, tolerance: tolerance))
    }

    @Test(.timeLimit(.minutes(1)))
    func reversalAndBothTransformPathsPreservePeriodicity() throws {
        let cyclic = try curve(rational: true).changingPeriodicOrigin(to: 7.25, tolerance: tolerance)
        let reversed = try cyclic.reversed(tolerance: tolerance)
        let rigid = RigidTransform3D.translated(by: Vector3D(x: 2, y: -3, z: 4))
        let affine = try AffineTransform3D(basisX: Vector3D(x: 2, y: 0, z: 0),
            basisY: Vector3D(x: 0.5, y: 3, z: 0), basisZ: Vector3D(x: 0, y: 0, z: 1),
            translation: Vector3D(x: -1, y: 2, z: 3))
        let translated = try rigid.applying(to: cyclic, tolerance: tolerance)
        let transformed = try affine.applying(to: cyclic, tolerance: tolerance)
        for result in [reversed, translated, transformed] {
            #expect(result.isPeriodic && result.periodicOrigin == cyclic.periodicOrigin)
        }
        for parameter in [3.25, 6, 7.25, 8, 12.25] {
            let reversedValue = try reversed.parameterDerivatives(at: parameter, tolerance: tolerance)
            let source = try cyclic.parameterDerivatives(at: 19.5 - parameter, tolerance: tolerance)
            #expect((reversedValue.position - source.position).length < 1e-12)
            #expect((reversedValue.firstDerivative + source.firstDerivative).length < 1e-12)
            #expect((reversedValue.secondDerivative - source.secondDerivative).length < 1e-12)
            let original = try cyclic.point(at: parameter, tolerance: tolerance)
            #expect((try translated.point(at: parameter, tolerance: tolerance)
                - rigid.applying(to: original)).length < 1e-12)
            #expect((try transformed.point(at: parameter, tolerance: tolerance)
                - affine.applying(to: original)).length < 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func codableAndValueIdentityRetainTheCyclicContract() throws {
        let cyclic = try curve(rational: true).changingPeriodicOrigin(to: -1, tolerance: tolerance)
        let value = Curve3D.bSpline(cyclic)
        let decoded = try JSONDecoder().decode(Curve3D.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        try decoded.validate(tolerance: tolerance)
        let unwrapped = BSplineCurve3D(degree: cyclic.degree, knots: cyclic.knots,
            controlPoints: cyclic.controlPoints, weights: cyclic.weights)
        #expect(cyclic != unwrapped)
        #expect(Set([cyclic, unwrapped]).count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedSeamKnotsDeclareOnlyTheirGuaranteedContinuity() throws {
        let cyclic = try BSplineCurve3D.periodic(degree: 3, cycleKnots: [0, 0, 1, 2, 3, 4],
            controlPoints: [.origin, Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 0, z: 0),
                Point3D(x: 1, y: -1, z: 0), Point3D(x: -1, y: 0, z: 0)], tolerance: tolerance)
        #expect(cyclic.periodicSeamContinuityOrder == 1)
        let unwrapped = BSplineCurve3D(degree: cyclic.degree, knots: cyclic.knots,
            controlPoints: cyclic.controlPoints, weights: cyclic.weights)
        let left = try unwrapped.parameterDerivatives(at: 4, tolerance: tolerance)
        let right = try unwrapped.parameterDerivatives(at: 0, tolerance: tolerance)
        #expect((left.position - right.position).length < 1e-12)
        #expect((left.firstDerivative - right.firstDerivative).length < 1e-12)
        #expect((left.secondDerivative - right.secondDerivative).length > 1e-3)
    }

    @Test(.timeLimit(.minutes(1)))
    func degreeOneCyclesKeepTheirCornerAndWrapTheirPolynomialThirdDerivative() throws {
        let cyclic = try BSplineCurve3D.periodic(degree: 1, cycleKnots: [0, 1, 2, 3, 4],
            controlPoints: [.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 1, y: 1, z: 0),
                Point3D(x: 0, y: 1, z: 0)], tolerance: tolerance)
        #expect(cyclic.periodicSeamContinuityOrder == 0)
        #expect(try Curve3D.bSpline(cyclic).thirdParameterDerivative(at: -7.5, tolerance: tolerance) == .zero)
        let cubic = try curve()
        for parameter in [3.25, 4.5, 7.5] {
            let expected = try Curve3D.bSpline(cubic).thirdParameterDerivative(at: parameter, tolerance: tolerance)
            let actual = try Curve3D.bSpline(cubic).thirdParameterDerivative(at: parameter + 10, tolerance: tolerance)
            #expect((expected - actual).length < 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedCyclesAndNonfiniteParametersFailExplicitly() throws {
        let valid = try curve()
        var wrongControls = valid
        wrongControls.controlPoints[4].x += 0.1
        var wrongWeights = valid
        wrongWeights.weights[4] = 2
        var wrongKnots = valid
        wrongKnots.knots[0] -= 0.1
        var wrongOrigin = valid
        wrongOrigin.periodicOrigin = .infinity
        for invalid in [wrongControls, wrongWeights, wrongKnots, wrongOrigin] {
            #expect(throws: (any Error).self) { try invalid.validate(tolerance: tolerance) }
        }
        for parameter in [Double.nan, .infinity, -.infinity] {
            #expect(throws: KernelError.self) {
                _ = try valid.normalizedParameter(parameter, tolerance: tolerance)
            }
        }
        let closed = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0), .origin])
        try closed.validate(tolerance: tolerance)
        #expect(!closed.isPeriodic && closed.domain == .closed(0, 1))
        #expect(throws: KernelError.self) { _ = try closed.changingPeriodicOrigin(to: 0.5, tolerance: tolerance) }
        #expect(throws: KernelError.self) {
            _ = try BSplineCurve3D.periodic(degree: .max, cycleKnots: [0, 1],
                controlPoints: [.origin], tolerance: tolerance)
        }
        let overflowingDegree = BSplineCurve3D(degree: .max, knots: [], controlPoints: [])
        #expect(throws: GeometryError.self) { try overflowingDegree.validate(tolerance: tolerance) }
    }

    @Test(.timeLimit(.minutes(1)))
    func pendingPeriodicEditsRefuseInsteadOfReturningAnOpenApproximation() throws {
        let cyclic = try curve()
        for operation in [
            { try cyclic.insertingKnot(4, tolerance: tolerance) },
            { try cyclic.trimmed(from: 7, to: 9, tolerance: tolerance) },
        ] {
            do {
                _ = try operation()
                Issue.record("An incomplete periodic edit returned success.")
            } catch let error as KernelError {
                #expect(error.code == .unsupportedCapability)
            }
        }
    }
}
