import CADCore
import CADGeometry
import Testing

@Suite("Exact Euclidean ruled B-spline surfaces")
struct ExactRuledBSplineSurfaceBuilderTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10,
        relative: 1.0e-11
    )

    @Test(.timeLimit(.minutes(1)))
    func differentRationalWeightFunctionsPreserveEveryEuclideanRuling() throws {
        let start = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.1, y: -0.2, z: 1.4),
                Point3D(x: 2.0, y: 0.0, z: 0.1),
            ],
            weights: [1.0, 0.35, 1.0]
        )
        let end = BSplineCurve3D(
            degree: 1,
            knots: [2.0, 2.0, 3.0, 5.0, 5.0],
            controlPoints: [
                Point3D(x: -0.2, y: 3.0, z: 0.4),
                Point3D(x: 0.8, y: 3.4, z: 1.8),
                Point3D(x: 2.3, y: 2.8, z: -0.3),
            ],
            weights: [1.0, 2.5, 0.7]
        )
        let surface = try ExactRuledBSplineSurfaceBuilder().build(
            startBoundary: start,
            endBoundary: end,
            tolerance: tolerance
        )

        #expect(surface.uDegree == 4)
        #expect(surface.vDegree == 1)
        #expect(surface.weights[0] == surface.weights[1])
        for uIndex in 0...32 {
            let u = Double(uIndex) / 32.0
            let startPoint = try start.point(at: u, tolerance: tolerance)
            let endPoint = try end.point(
                at: 2.0 + 3.0 * u,
                tolerance: tolerance
            )
            for vIndex in 0...8 {
                let v = Double(vIndex) / 8.0
                let expected = startPoint + (endPoint - startPoint) * v
                let actual = try surface.point(
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
                #expect((actual - expected).length <= tolerance.distance * 8.0)
            }
            let derivatives = try surface.parameterDerivatives(
                atU: u,
                v: 0.37,
                tolerance: tolerance
            )
            #expect(
                (derivatives.tangentV - (endPoint - startPoint)).length
                    <= tolerance.distance * 32.0
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func resultDegreeBudgetRejectsBeforeConstructingAnInexactFallback() throws {
        let boundary = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.5, y: 0.0, z: 0.2),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.5, 1.0]
        )
        do {
            _ = try ExactRuledBSplineSurfaceBuilder(
                maximumResultDegree: 1
            ).build(
                startBoundary: boundary,
                endBoundary: boundary,
                tolerance: tolerance
            )
            Issue.record("Expected the exact result-degree budget to reject.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }
}
