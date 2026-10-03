import CADCore
@testable import CADGeometry
import Testing

@Suite("Exact periodic B-spline restrictions")
struct PeriodicBSplineRestrictionTests {
    private let tolerance = ModelingTolerance.standard

    private func curve(degree: Int = 3, rational: Bool = true) throws -> BSplineCurve3D {
        try .periodic(degree: degree, cycleKnots: [3, 3.5, 5, 6, 8],
            controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 2, z: 0.5),
                Point3D(x: -1, y: 0, z: 1), Point3D(x: 0, y: -2, z: 0.5)],
            weights: rational ? [1, 2, 0.5, 1.5] : nil, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func restrictionsPreserveRationalAndPolynomialCurvesAcrossEverySeam() throws {
        for degree in [1, 2, 3, 5] {
            for rational in [false, true] {
                let cyclic = try curve(degree: degree, rational: rational)
                for (lower, upper) in [(7.25, 9.25), (-7.0, 13.0), (3.0, 8.0), (8.0, 13.0)] {
                    let restriction = try cyclic.trimmed(from: lower, to: upper, tolerance: tolerance)
                    #expect(!restriction.isPeriodic && restriction.periodicOrigin == nil)
                    #expect(restriction.domain == .closed(lower, upper))
                    #expect(restriction.knots.prefix(degree + 1).allSatisfy { $0 == lower })
                    #expect(restriction.knots.suffix(degree + 1).allSatisfy { $0 == upper })
                    for index in 0...160 {
                        let parameter = lower + (upper - lower) * Double(index) / 160
                        let expected = try cyclic.parameterDerivatives(at: parameter, tolerance: tolerance)
                        let actual = try restriction.parameterDerivatives(at: parameter, tolerance: tolerance)
                        #expect((actual.position - expected.position).length < 1e-11)
                        // Degree-one knots retain a corner; the terminal restriction uses the left derivative.
                        if degree > 1 || index < 160 {
                            #expect((actual.firstDerivative - expected.firstDerivative).length < 1e-10)
                        }
                        if degree > 2 {
                            #expect((actual.secondDerivative - expected.secondDerivative).length < 1e-9)
                        }
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedSeamsRetainTheirOneSidedDerivativesInRestrictions() throws {
        let cyclic = try BSplineCurve3D.periodic(degree: 3, cycleKnots: [0, 0, 1, 2, 3, 4],
            controlPoints: [.origin, Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 0, z: 0),
                Point3D(x: 1, y: -1, z: 0), Point3D(x: -1, y: 0, z: 0)], tolerance: tolerance)
        let restriction = try cyclic.trimmed(from: 3.5, to: 4.5, tolerance: tolerance)
        for parameter in [3.5, 3.9, 4, 4.1, 4.5] {
            let expected = try cyclic.parameterDerivatives(at: parameter, tolerance: tolerance)
            let actual = try restriction.parameterDerivatives(at: parameter, tolerance: tolerance)
            #expect((expected.position - actual.position).length < 1e-12)
            #expect((expected.firstDerivative - actual.firstDerivative).length < 1e-12)
            #expect((expected.secondDerivative - actual.secondDerivative).length < 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preparedProjectionUsesTheChosenFundamentalIntervalOrExplicitRange() throws {
        let cyclic = try curve().changingPeriodicOrigin(to: 7.25, tolerance: tolerance)
        let prepared = try ValidatedCurve3D(.bSpline(cyclic), tolerance: tolerance)
        for parameter in [7.25, 7.8, 8.1, 9.5, 12.1] {
            let point = try prepared.point(at: parameter)
            let projection = try prepared.parameterProjection(of: point)
            #expect(abs(projection.parameter - parameter) < 1e-7)
            #expect(projection.residual <= tolerance.distance)
        }
        let parameter = -1.25
        let point = try prepared.point(at: parameter)
        let options = CurveParameterProjectionOptions(parameterRange: try ScalarInterval(lower: -2, upper: 0))
        #expect(abs(try prepared.parameterProjection(of: point, options: options).parameter - parameter) < 1e-7)
        do {
            _ = try prepared.parameterProjection(of: point,
                options: .init(parameterRange: try ScalarInterval(lower: -2, upper: 10)))
            Issue.record("Distinct period representatives were silently merged.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
        }
        #expect(throws: KernelError.self) {
            _ = try prepared.parameterProjection(of: Point3D(x: 100, y: 100, z: 100))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func intervalBoundsEncloseDerivativesOnBothSidesOfTheSeam() throws {
        let cyclic = try curve()
        let prepared = try ValidatedCurve3D(.bSpline(cyclic), tolerance: tolerance)
        let interval = try ScalarInterval(lower: 7.75, upper: 8.25)
        let bounds = try prepared.tessellationIntervalEvaluation(interval).bounds
        #expect(bounds.secondDerivativeMagnitudeUpperBound.isFinite)
        for index in 0...100 {
            let parameter = interval.lower + interval.width * Double(index) / 100
            let derivatives = try cyclic.parameterDerivatives(at: parameter, tolerance: tolerance)
            #expect(derivatives.secondDerivative.length <= bounds.secondDerivativeMagnitudeUpperBound)
        }
        let middle = try prepared.point(at: interval.midpoint)
        let left = try prepared.point(at: interval.lower)
        let right = try prepared.point(at: interval.upper)
        #expect((middle - (left + (right - left) * 0.5)).length <= bounds.chordDeviationUpperBound)
    }

    @Test(.timeLimit(.minutes(1)))
    func cornerCrossingDoesNotReturnAFiniteSmoothDerivativeCertificate() throws {
        let cyclic = try curve(degree: 1, rational: false)
        let prepared = try ValidatedCurve3D(.bSpline(cyclic), tolerance: tolerance)
        do {
            _ = try prepared.tessellationIntervalEvaluation(ScalarInterval(lower: 7.75, upper: 8.25))
            Issue.record("A periodic corner was certified using only its zero span-wise second derivatives.")
        } catch let error as KernelError {
            #expect(error.code == .singularGeometry)
        }
        #expect(throws: KernelError.self) {
            _ = try prepared.tessellationIntervalEvaluation(ScalarInterval(lower: 7.75, upper: 8.25),
                usingCertifiedSecondDerivativeMagnitudeUpperBound: 0)
        }
        let affine = try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)
        let images: [Curve3D] = [
            .rigidImage(try RigidImageCurve3D(source: .bSpline(cyclic),
                transform: .translated(by: .zero), tolerance: tolerance)),
            .affineImage(try AffineImageCurve3D(source: .bSpline(cyclic),
                transform: affine, tolerance: tolerance)),
        ]
        for image in images {
            let imagePrepared = try ValidatedCurve3D(image, tolerance: tolerance)
            #expect(throws: KernelError.self) {
                _ = try imagePrepared.tessellationIntervalEvaluation(ScalarInterval(lower: 7.75, upper: 8.25),
                    usingCertifiedSecondDerivativeMagnitudeUpperBound: 0)
            }
        }
        let firstSpan = try prepared.tessellationIntervalEvaluation(ScalarInterval(lower: 7.75, upper: 8)).bounds
        let nextSpan = try prepared.tessellationIntervalEvaluation(ScalarInterval(lower: 8, upper: 8.25)).bounds
        #expect(firstSpan.chordDeviationUpperBound < 1e-12)
        #expect(nextSpan.chordDeviationUpperBound < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func expansionBudgetIncludesBoundaryInsertionWorkspace() throws {
        let cyclic = try curve()
        do {
            _ = try cyclic.trimmed(from: 3, to: 8,
                expansionOptions: .init(maximumControlPointCount: 15), tolerance: tolerance)
            Issue.record("Boundary insertion workspace exceeded the control budget.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func expansionBudgetAndMalformedRangesFailBeforeReturningAnyCurve() throws {
        let cyclic = try curve()
        for (lower, upper) in [(8.0, 8.0), (9.0, 7.0), (Double.nan, 8.0), (7.0, Double.infinity)] {
            do {
                _ = try cyclic.trimmed(from: lower, to: upper, tolerance: tolerance)
                Issue.record("An invalid periodic restriction returned success.")
            } catch let error as KernelError {
                #expect(error.code == .invalidInput)
            }
        }
        for (lower, upper) in [(7.0, 9.0), (-1e100, 1e100)] {
            do {
                _ = try cyclic.trimmed(from: lower, to: upper,
                    expansionOptions: .init(maximumControlPointCount: 4), tolerance: tolerance)
                Issue.record("Periodic expansion exceeded its explicit budget.")
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
            }
        }
        #expect(throws: KernelError.self) {
            _ = try cyclic.trimmed(from: 7, to: 9,
                expansionOptions: .init(maximumControlPointCount: 0), tolerance: tolerance)
        }
    }
}
