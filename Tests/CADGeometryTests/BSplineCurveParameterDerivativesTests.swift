import Testing
import CADCore
@testable import CADGeometry

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
