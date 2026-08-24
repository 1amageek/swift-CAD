import CADCore
import CADGeometry
import Testing

@Suite("Surface parameter derivatives through third order")
struct SurfaceParameterThirdOrderDerivativesTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-10,
        angle: 1.0e-11,
        relative: 1.0e-12
    )

    @Test(.timeLimit(.minutes(1)))
    func analyticThirdOrderDerivativesPreserveLowerOrderTruth() throws {
        let u = 0.43
        let v = 0.61
        let surfaces: [Surface3D] = [
            .plane(Plane3D(origin: .origin, normal: .unitZ)),
            .cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 2.0)),
            .analytic(.plane(origin: .origin, normal: .unitY)),
            .analytic(.cylinder(origin: .origin, axis: .unitX, radius: 1.7)),
            .analytic(.cone(apex: .origin, axis: .unitZ, halfAngle: 0.37)),
            .analytic(.sphere(center: .origin, radius: 2.3)),
            .analytic(.torus(
                center: .origin,
                axis: .unitY,
                majorRadius: 3.1,
                minorRadius: 0.8
            )),
        ]

        for surface in surfaces {
            let lower = try surface.parameterDerivatives(
                atU: u,
                v: v,
                tolerance: tolerance
            )
            let third = try surface.parameterDerivativesThroughThirdOrder(
                atU: u,
                v: v,
                tolerance: tolerance
            )

            expectApproximatelyEqual(third.position, lower.position)
            expectApproximatelyEqual(third.tangentU, lower.tangentU)
            expectApproximatelyEqual(third.tangentV, lower.tangentV)
            expectApproximatelyEqual(
                third.secondDerivativeUU,
                lower.secondDerivativeUU
            )
            expectApproximatelyEqual(
                third.secondDerivativeUV,
                lower.secondDerivativeUV
            )
            expectApproximatelyEqual(
                third.secondDerivativeVV,
                lower.secondDerivativeVV
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticThirdOrderDerivativesMatchClosedForms() throws {
        let u = 0.43
        let v = 0.61

        let plane = try Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        )).parameterDerivativesThroughThirdOrder(
            atU: u,
            v: v,
            tolerance: tolerance
        )
        expectApproximatelyEqual(plane.thirdDerivativeUUU, .zero)
        expectApproximatelyEqual(plane.thirdDerivativeUUV, .zero)
        expectApproximatelyEqual(plane.thirdDerivativeUVV, .zero)
        expectApproximatelyEqual(plane.thirdDerivativeVVV, .zero)

        let cylinder = try Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        )).parameterDerivativesThroughThirdOrder(
            atU: u,
            v: v,
            tolerance: tolerance
        )
        expectApproximatelyEqual(
            cylinder.thirdDerivativeUUU,
            -cylinder.tangentU
        )
        expectApproximatelyEqual(cylinder.thirdDerivativeUUV, .zero)
        expectApproximatelyEqual(cylinder.thirdDerivativeUVV, .zero)
        expectApproximatelyEqual(cylinder.thirdDerivativeVVV, .zero)

        let sphere = try Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.3
        )).parameterDerivativesThroughThirdOrder(
            atU: u,
            v: v,
            tolerance: tolerance
        )
        expectApproximatelyEqual(sphere.thirdDerivativeUUU, -sphere.tangentU)
        expectApproximatelyEqual(sphere.thirdDerivativeUVV, -sphere.tangentU)
        expectApproximatelyEqual(sphere.thirdDerivativeVVV, -sphere.tangentV)

        let torus = try Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitY,
            majorRadius: 3.1,
            minorRadius: 0.8
        )).parameterDerivativesThroughThirdOrder(
            atU: u,
            v: v,
            tolerance: tolerance
        )
        expectApproximatelyEqual(torus.thirdDerivativeUUU, -torus.tangentU)
        expectApproximatelyEqual(torus.thirdDerivativeVVV, -torus.tangentV)
    }

    @Test(.timeLimit(.minutes(1)))
    func cubicPolynomialSurfaceMatchesExactThirdOrderJet() throws {
        let surface = makeCubicPolynomialSurface()
        let u = 0.37
        let v = 0.42

        let derivatives = try surface.parameterDerivativesThroughThirdOrder(
            atU: u,
            v: v,
            tolerance: tolerance
        )

        let uSquared = u * u
        let vSquared = v * v
        let z = uSquared * u
            + 2.0 * uSquared * v
            + 3.0 * u * vSquared
            + 4.0 * vSquared * v
        expectApproximatelyEqual(
            derivatives.position,
            Point3D(x: u, y: v, z: z)
        )
        expectApproximatelyEqual(
            derivatives.tangentU,
            Vector3D(
                x: 1.0,
                y: 0.0,
                z: 3.0 * u * u + 4.0 * u * v + 3.0 * v * v
            )
        )
        expectApproximatelyEqual(
            derivatives.tangentV,
            Vector3D(
                x: 0.0,
                y: 1.0,
                z: 2.0 * u * u + 6.0 * u * v + 12.0 * v * v
            )
        )
        expectApproximatelyEqual(
            derivatives.secondDerivativeUU,
            Vector3D(x: 0.0, y: 0.0, z: 6.0 * u + 4.0 * v)
        )
        expectApproximatelyEqual(
            derivatives.secondDerivativeUV,
            Vector3D(x: 0.0, y: 0.0, z: 4.0 * u + 6.0 * v)
        )
        expectApproximatelyEqual(
            derivatives.secondDerivativeVV,
            Vector3D(x: 0.0, y: 0.0, z: 6.0 * u + 24.0 * v)
        )
        expectApproximatelyEqual(
            derivatives.thirdDerivativeUUU,
            Vector3D(x: 0.0, y: 0.0, z: 6.0)
        )
        expectApproximatelyEqual(
            derivatives.thirdDerivativeUUV,
            Vector3D(x: 0.0, y: 0.0, z: 4.0)
        )
        expectApproximatelyEqual(
            derivatives.thirdDerivativeUVV,
            Vector3D(x: 0.0, y: 0.0, z: 6.0)
        )
        expectApproximatelyEqual(
            derivatives.thirdDerivativeVVV,
            Vector3D(x: 0.0, y: 0.0, z: 24.0)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalSurfaceMatchesIndependentQuotientDerivatives() throws {
        let surface = makeRationalSurface()
        let u = 0.31
        let v = 0.47
        let denominator = 1.0 + u
        let value = u / denominator
        let denominatorSquared = denominator * denominator
        let denominatorCubed = denominatorSquared * denominator
        let denominatorFourth = denominatorCubed * denominator
        let first = 1.0 / denominatorSquared
        let second = -2.0 / denominatorCubed
        let third = 6.0 / denominatorFourth

        let derivatives = try surface.parameterDerivativesThroughThirdOrder(
            atU: u,
            v: v,
            tolerance: tolerance
        )

        expectApproximatelyEqual(
            derivatives.position,
            Point3D(x: value, y: v, z: v * value)
        )
        expectApproximatelyEqual(
            derivatives.tangentU,
            Vector3D(x: first, y: 0.0, z: v * first)
        )
        expectApproximatelyEqual(
            derivatives.tangentV,
            Vector3D(x: 0.0, y: 1.0, z: value)
        )
        expectApproximatelyEqual(
            derivatives.secondDerivativeUU,
            Vector3D(x: second, y: 0.0, z: v * second)
        )
        expectApproximatelyEqual(
            derivatives.secondDerivativeUV,
            Vector3D(x: 0.0, y: 0.0, z: first)
        )
        expectApproximatelyEqual(derivatives.secondDerivativeVV, .zero)
        expectApproximatelyEqual(
            derivatives.thirdDerivativeUUU,
            Vector3D(x: third, y: 0.0, z: v * third)
        )
        expectApproximatelyEqual(
            derivatives.thirdDerivativeUUV,
            Vector3D(x: 0.0, y: 0.0, z: second)
        )
        expectApproximatelyEqual(derivatives.thirdDerivativeUVV, .zero)
        expectApproximatelyEqual(derivatives.thirdDerivativeVVV, .zero)
    }

    @Test(.timeLimit(.minutes(1)))
    func parametersOutsideBSplineDomainFailExplicitly() throws {
        let surface = makeRationalSurface()

        #expect(throws: GeometryError.self) {
            try surface.parameterDerivativesThroughThirdOrder(
                atU: -0.1,
                v: 0.5,
                tolerance: tolerance
            )
        }
    }

    private func makeCubicPolynomialSurface() -> BSplineSurface3D {
        let zControlPoints: [[Double]] = [
            [0.0, 0.0, 0.0, 1.0],
            [0.0, 0.0, 2.0 / 9.0, 5.0 / 3.0],
            [0.0, 1.0 / 3.0, 10.0 / 9.0, 10.0 / 3.0],
            [4.0, 5.0, 20.0 / 3.0, 10.0],
        ]
        let controlPoints = (0..<4).map { vIndex in
            (0..<4).map { uIndex in
                Point3D(
                    x: Double(uIndex) / 3.0,
                    y: Double(vIndex) / 3.0,
                    z: zControlPoints[vIndex][uIndex]
                )
            }
        }
        return BSplineSurface3D(
            uDegree: 3,
            vDegree: 3,
            uKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: controlPoints
        )
    }

    private func makeRationalSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.5, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 0.5, y: 1.0, z: 0.5),
                ],
            ],
            weights: [
                [1.0, 2.0],
                [1.0, 2.0],
            ]
        )
    }

    private func expectApproximatelyEqual(
        _ actual: Point3D,
        _ expected: Point3D,
        accuracy: Double = 1.0e-9
    ) {
        #expect(abs(actual.x - expected.x) <= accuracy)
        #expect(abs(actual.y - expected.y) <= accuracy)
        #expect(abs(actual.z - expected.z) <= accuracy)
    }

    private func expectApproximatelyEqual(
        _ actual: Vector3D,
        _ expected: Vector3D,
        accuracy: Double = 1.0e-9
    ) {
        #expect(abs(actual.x - expected.x) <= accuracy)
        #expect(abs(actual.y - expected.y) <= accuracy)
        #expect(abs(actual.z - expected.z) <= accuracy)
    }
}
