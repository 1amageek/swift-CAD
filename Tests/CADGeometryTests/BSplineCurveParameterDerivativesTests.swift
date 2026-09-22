import Testing
import CADCore
@testable import CADGeometry

@Test(.timeLimit(.minutes(1)))
func nearlyUnitWeightsRetainRationalDerivativeCertificate() throws {
    let spline = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
        controlPoints: [.origin, Point3D(x: 1, y: 0, z: 0),
            Point3D(x: 2, y: 0, z: 0), Point3D(x: 3, y: 0, z: 0)],
        weights: [1, 1 + 5e-13, 1, 1])
    let bounds = try Curve3D.bSpline(spline).tessellationIntervalBounds(
        ScalarInterval(lower: 0, upper: 1), tolerance: .standard)
    for parameter in [0.0, 0.25, 0.5, 0.75, 1] {
        let derivative = try spline.parameterDerivatives(at: parameter, tolerance: .standard)
        #expect(derivative.secondDerivative.length <= bounds.secondDerivativeMagnitudeUpperBound)
    }
    #expect(bounds.secondDerivativeMagnitudeUpperBound > 1e-12)
}

@Test(.timeLimit(.minutes(1)))
func quadraticBasisMatchesGeneralRecurrenceAndRationalCurve() throws {
    let knots: [Double] = [2, 2, 2, 5, 5, 5]
    for index in 0...100 {
        let t = 2 + 3 * Double(index) / 100
        for order in 0...3 {
            let actual = BSplineBasis.nonzeroValues(parameter: t, degree: 2,
                derivativeOrder: order, knots: knots, count: 3)
            let expected = BSplineBasis.derivativeValues(parameter: t, degree: 2,
                derivativeOrder: order, knots: knots, count: 3)
            #expect(actual.startIndex == 0)
            for (a, b) in zip(actual.values, expected) { #expect(abs(a - b) < 1e-13) }
        }
    }
    let curve = BSplineCurve3D(degree: 2, knots: knots,
        controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 1, y: 1, z: 0),
            Point3D(x: 0, y: 1, z: 0)], weights: [1, 0.5.squareRoot(), 1])
    let general = try curve.insertingKnot(3.5, tolerance: .standard)
    for index in 0...100 {
        let t = 2 + 3 * Double(index) / 100
        let actual = try curve.parameterDerivatives(at: t, tolerance: .standard)
        let expected = try general.parameterDerivatives(at: t, tolerance: .standard)
        #expect((actual.position - expected.position).length < 1e-12)
        #expect((actual.firstDerivative - expected.firstDerivative).length < 1e-12)
        #expect((actual.secondDerivative - expected.secondDerivative).length < 1e-12)
    }
}

@Test(.timeLimit(.minutes(1)))
func cubicParameterDerivativesMatchRationalBasis() throws {
    let polynomial = BSplineCurve3D(degree: 3, knots: [2, 2, 2, 2, 5, 5, 5, 5],
        controlPoints: [Point3D(x: 1, y: -2, z: 3), Point3D(x: 2, y: 4, z: -1),
            Point3D(x: -3, y: 1, z: 2), Point3D(x: 5, y: -2, z: 1)])
    var rational = polynomial
    rational.weights = [2, 2, 2, 2]
    for index in 0...100 {
        let t = 2 + 3 * Double(index) / 100
        let actual = try polynomial.parameterDerivatives(at: t, tolerance: .standard)
        let expected = try rational.parameterDerivatives(at: t, tolerance: .standard)
        #expect((actual.position - expected.position).length < 1e-12)
        #expect((actual.firstDerivative - expected.firstDerivative).length < 1e-12)
        #expect((actual.secondDerivative - expected.secondDerivative).length < 1e-12)
    }
    #expect(throws: GeometryError.self) {
        try polynomial.parameterDerivatives(at: 6, tolerance: .standard)
    }
}

@Test(.timeLimit(.minutes(1)))
func bSplineRawParameterDerivativesAllowStationaryEndpoint() throws {
    let curve = BSplineCurve3D(
        degree: 3,
        knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
        controlPoints: [
            .origin,
            .origin,
            Point3D(x: 0.001, y: 0.0, z: 0.001),
            Point3D(x: 0.002, y: 0.0, z: 0.002),
        ]
    )

    let derivatives = try curve.parameterDerivatives(
        at: 0.0,
        tolerance: .standard
    )

    #expect(derivatives.position == .origin)
    #expect(derivatives.firstDerivative == .zero)
    #expect(derivatives.secondDerivative.length > 0.0)
    #expect(throws: KernelError.self) {
        _ = try curve.differentialGeometry(at: 0.0, tolerance: .standard)
    }

    let bounds = try Curve3D.bSpline(curve).tessellationIntervalBounds(
        try ScalarInterval(lower: 0.0, upper: 0.25),
        tolerance: .standard
    )
    #expect(bounds.tangentDeviationUpperBound.isFinite)
}

@Test(.timeLimit(.minutes(1)))
func stationaryEndpointBSplineTessellationBoundsConverge() throws {
    let curve = Curve3D.bSpline(BSplineCurve3D(
        degree: 3,
        knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
        controlPoints: [
            Point3D(x: -0.002, y: -0.001, z: 0.0),
            Point3D(x: -0.002, y: -0.001, z: 0.0),
            Point3D(x: 0.0005, y: -0.00125, z: 0.0033333333333333335),
            Point3D(x: 0.0005, y: -0.00125, z: 0.005),
        ]
    ))
    var pending = [try ScalarInterval(lower: 0.0, upper: 1.0)]
    var acceptedCount = 0
    while let interval = pending.popLast() {
        let bounds: CurveTessellationIntervalBounds
        do {
            bounds = try curve.tessellationIntervalBounds(
                interval,
                tolerance: .standard
            )
        } catch {
            Issue.record(
                "Stationary curve bound failed on [\(interval.lower), \(interval.upper)]."
            )
            throw error
        }
        if bounds.chordDeviationUpperBound <= 1.0e-4,
           bounds.tangentDeviationUpperBound <= 1.0e-3 {
            acceptedCount += 1
            continue
        }
        let middle = interval.midpoint
        pending.append(try ScalarInterval(lower: middle, upper: interval.upper))
        pending.append(try ScalarInterval(lower: interval.lower, upper: middle))
        #expect(pending.count + acceptedCount < 65_536)
    }
    #expect(acceptedCount > 1)
}
