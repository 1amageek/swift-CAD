import CADCore
@testable import CADGeometry
import Testing

@Suite("Exact periodic B-spline refinement")
struct PeriodicBSplineRefinementTests {
    private let tolerance = ModelingTolerance.standard

    private func curve(degree: Int = 3, rational: Bool = true) throws -> BSplineCurve3D {
        try .periodic(degree: degree, cycleKnots: [3, 3.5, 5, 6, 8],
            controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 2, z: 0.5),
                Point3D(x: -1, y: 0, z: 1), Point3D(x: 0, y: -2, z: 0.5)],
            weights: rational ? [1, 2, 0.5, 1.5] : nil, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func interiorRefinementRetainsThePeriodicLocus() throws {
        let source = try curve()
        let result = try source.insertingKnot(4.25, tolerance: tolerance)
        #expect(result.isPeriodic && result.controlPointCount == source.controlPointCount + 1)
        for index in 0...100 {
            let parameter = -7 + Double(index) * 0.2
            #expect((try result.point(at: parameter, tolerance: tolerance)
                - source.point(at: parameter, tolerance: tolerance)).length < 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func seamAndNonuniformRefinementPreserveRationalDerivativesAcrossCycles() throws {
        for degree in [1, 2, 3, 5, 9] {
            for rational in [false, true] {
                let source = try curve(degree: degree, rational: rational)
                    .changingPeriodicOrigin(to: 7.25, tolerance: tolerance)
                let parameters = degree == 1 ? [3.25, 7.25] : [3, 3.25, 3.5, 7.25, 8]
                for inserted in parameters {
                    let result = try source.insertingKnot(inserted, tolerance: tolerance)
                    #expect(result.isPeriodic && result.periodicOrigin == 7.25)
                    #expect(result.domain == source.domain)
                    #expect(result.controlPointCount == source.controlPointCount + 1)
                    for index in 0...200 {
                        let parameter = -7 + Double(index) * 0.1
                        let expected = try source.parameterDerivatives(at: parameter, tolerance: tolerance)
                        let actual = try result.parameterDerivatives(at: parameter, tolerance: tolerance)
                        #expect((expected.position - actual.position).length < 1e-11)
                        #expect((expected.firstDerivative - actual.firstDerivative).length < 1e-10)
                        #expect((expected.secondDerivative - actual.secondDerivative).length < 1e-9)
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func insertionRepresentativesAgreeAndRepeatedInsertionsRetainTheirLocus() throws {
        let source = try curve()
        let expected = try source.insertingKnot(4.25, tolerance: tolerance)
        for parameter in [-10.75, -0.75, 9.25, 24.25] {
            #expect(try source.insertingKnot(parameter, tolerance: tolerance) == expected)
        }
        var result = source
        for _ in 0..<source.degree {
            result = try result.insertingKnot(4.25, tolerance: tolerance)
        }
        #expect(throws: KernelError.self) { _ = try result.insertingKnot(4.25, tolerance: tolerance) }
        for parameter in [3.25, 4.25, 5.25, 7.25, 8, 13.25] {
            #expect((try result.point(at: parameter, tolerance: tolerance)
                - source.point(at: parameter, tolerance: tolerance)).length < 1e-12)
        }
        let trimmed = try result.trimmed(from: 7.5, to: 9.5, tolerance: tolerance)
        #expect((try trimmed.point(at: 8.25, tolerance: tolerance)
            - source.point(at: 8.25, tolerance: tolerance)).length < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func seamMultiplicityLimitsAreExplicitWithoutDestroyingHigherActualContinuity() throws {
        let source = try curve()
        var result = source
        for _ in 1..<source.degree {
            result = try result.insertingKnot(3, tolerance: tolerance)
        }
        #expect(result.periodicSeamContinuityOrder == 0)
        let open = BSplineCurve3D(degree: result.degree, knots: result.knots,
            controlPoints: result.controlPoints, weights: result.weights)
        let left = try open.parameterDerivatives(at: 8, tolerance: tolerance)
        let right = try open.parameterDerivatives(at: 3, tolerance: tolerance)
        #expect((left.position - right.position).length < 1e-12)
        #expect((left.firstDerivative - right.firstDerivative).length < 1e-11)
        #expect((left.secondDerivative - right.secondDerivative).length < 1e-10)
        do {
            _ = try result.insertingKnot(8, tolerance: tolerance)
            Issue.record("Periodic refinement exceeded the seam multiplicity.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedKnotsOnBothRepresentationsOfTheSeamKeepTheirCycle() throws {
        for cycleKnots in [[0.0, 0, 1, 2, 3, 4], [0.0, 1, 2, 3, 4, 4]] {
            let source = try BSplineCurve3D.periodic(degree: 3, cycleKnots: cycleKnots,
                controlPoints: [.origin, Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 0, z: 0),
                    Point3D(x: 1, y: -1, z: 0), Point3D(x: -1, y: 0, z: 0)],
                weights: [1, 2, 1, 0.5, 1.5], tolerance: tolerance)
            let refined = try source.insertingKnot(0, tolerance: tolerance)
            #expect(refined.periodicSeamContinuityOrder == 0)
            for parameter in [-4.25, 0, 0.25, 3.75, 4, 8.25] {
                let expected = try source.parameterDerivatives(at: parameter, tolerance: tolerance)
                let actual = try refined.parameterDerivatives(at: parameter, tolerance: tolerance)
                #expect((expected.position - actual.position).length < 1e-11)
                #expect((expected.firstDerivative - actual.firstDerivative).length < 1e-10)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedParametersAndIndependentBudgetsFailBeforeReturningAnyCurve() throws {
        let source = try curve()
        for parameter in [Double.nan, .infinity, -.infinity] {
            do {
                _ = try source.insertingKnot(parameter, tolerance: tolerance)
                Issue.record("A nonfinite periodic insertion returned success.")
            } catch let error as KernelError {
                #expect(error.code == .invalidInput)
            }
        }
        for options in [PeriodicBSplineExpansionOptions(maximumControlPointCount: 8),
                        .init(maximumKnotInsertionWork: 1)] {
            do {
                _ = try source.insertingKnot(4.25, expansionOptions: options, tolerance: tolerance)
                Issue.record("Periodic refinement exceeded its explicit resource budget.")
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
            }
        }
        #expect(throws: KernelError.self) {
            _ = try source.insertingKnot(4.25, expansionOptions: .init(maximumKnotInsertionWork: 0), tolerance: tolerance)
        }
    }
}
