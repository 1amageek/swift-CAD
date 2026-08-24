import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("Certified procedural offset surfaces")
struct OffsetSurface3DTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-10,
        angle: 1.0e-11,
        relative: 1.0e-12
    )

    @Test(.timeLimit(.minutes(1)))
    func analyticOffsetsMatchEquivalentAnalyticSurfacesThroughThirdOrder() throws {
        let distance = 0.37
        let cases: [(source: Surface3D, expected: Surface3D)] = [
            (
                .analytic(.cylinder(
                    origin: Point3D(x: 0.2, y: -0.3, z: 0.7),
                    axis: .unitZ,
                    radius: 1.8
                )),
                .analytic(.cylinder(
                    origin: Point3D(x: 0.2, y: -0.3, z: 0.7),
                    axis: .unitZ,
                    radius: 1.8 + distance
                ))
            ),
            (
                .analytic(.sphere(
                    center: Point3D(x: -0.4, y: 0.6, z: 1.1),
                    radius: 2.2
                )),
                .analytic(.sphere(
                    center: Point3D(x: -0.4, y: 0.6, z: 1.1),
                    radius: 2.2 + distance
                ))
            ),
            (
                .analytic(.torus(
                    center: Point3D(x: 0.5, y: 0.8, z: -0.2),
                    axis: .unitZ,
                    majorRadius: 3.4,
                    minorRadius: 0.9
                )),
                .analytic(.torus(
                    center: Point3D(x: 0.5, y: 0.8, z: -0.2),
                    axis: .unitZ,
                    majorRadius: 3.4,
                    minorRadius: 0.9 + distance
                ))
            ),
        ]

        for pair in cases {
            let offset = OffsetSurface3D(
                source: pair.source,
                distance: distance
            )
            for (u, v) in [(0.37, 0.28), (1.41, -0.34), (4.73, 0.81)] {
                let actual = try offset.parameterDerivativesThroughThirdOrder(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
                let expected = try pair.expected.parameterDerivativesThroughThirdOrder(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
                expectApproximatelyEqual(actual, expected)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func planarBSplineOffsetIsAnExactNormalTranslation() throws {
        let source = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 1.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 2.0),
                    Point3D(x: 1.0, y: 1.0, z: 3.0),
                ],
            ]
        ))
        let distance = 0.65
        let normal = try Vector3D(x: -1.0, y: -2.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let offset = OffsetSurface3D(source: source, distance: distance)
        let u = 0.31
        let v = 0.73

        let sourceDerivatives = try source.parameterDerivativesThroughThirdOrder(
            atU: u,
            v: v,
            tolerance: tolerance
        )
        let actual = try offset.parameterDerivativesThroughThirdOrder(
            atU: u,
            v: v,
            tolerance: tolerance
        )

        expectApproximatelyEqual(
            actual.position,
            sourceDerivatives.position + normal * distance
        )
        expectApproximatelyEqual(actual.tangentU, sourceDerivatives.tangentU)
        expectApproximatelyEqual(actual.tangentV, sourceDerivatives.tangentV)
        expectApproximatelyEqual(
            actual.secondDerivativeUU,
            sourceDerivatives.secondDerivativeUU
        )
        expectApproximatelyEqual(
            actual.secondDerivativeUV,
            sourceDerivatives.secondDerivativeUV
        )
        expectApproximatelyEqual(
            actual.secondDerivativeVV,
            sourceDerivatives.secondDerivativeVV
        )
        expectApproximatelyEqual(
            actual.thirdDerivativeUUU,
            sourceDerivatives.thirdDerivativeUUU
        )
        expectApproximatelyEqual(
            actual.thirdDerivativeUUV,
            sourceDerivatives.thirdDerivativeUUV
        )
        expectApproximatelyEqual(
            actual.thirdDerivativeUVV,
            sourceDerivatives.thirdDerivativeUVV
        )
        expectApproximatelyEqual(
            actual.thirdDerivativeVVV,
            sourceDerivatives.thirdDerivativeVVV
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func singularSourceFrameFailsExplicitly() throws {
        let source = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [.origin, Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [.origin, Point3D(x: 1.0, y: 0.0, z: 0.0)],
            ]
        ))
        let offset = OffsetSurface3D(source: source, distance: 0.2)

        do {
            _ = try offset.point(u: 0.5, v: 0.5, tolerance: tolerance)
            Issue.record("A singular source frame must not produce an offset point.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularSystem)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceIntegrationPreservesNestedOffsetsAndCodableOwnership() throws {
        let base = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 1.4
        ))
        let first = Surface3D.procedural(.offset(OffsetSurface3D(
            source: base,
            distance: 0.2
        )))
        let nested = Surface3D.procedural(.offset(OffsetSurface3D(
            source: first,
            distance: 0.35
        )))
        let expected = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 1.95
        ))

        let actualDerivatives = try nested.parameterDerivativesThroughThirdOrder(
            atU: 0.73,
            v: -0.41,
            tolerance: tolerance
        )
        let expectedDerivatives = try expected.parameterDerivativesThroughThirdOrder(
            atU: 0.73,
            v: -0.41,
            tolerance: tolerance
        )
        expectApproximatelyEqual(actualDerivatives, expectedDerivatives)

        let encoded = try JSONEncoder().encode(nested)
        let decoded = try JSONDecoder().decode(Surface3D.self, from: encoded)
        #expect(decoded == nested)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedOffsetEnclosureContainsSampledSecondOrderTruth() throws {
        let surface = Surface3D.procedural(.offset(OffsetSurface3D(
            source: .bSpline(makeCurvedSurface()),
            distance: 0.12
        )))
        let parameterBox = SurfaceParameterBox(
            u: try ScalarInterval(lower: 0.25, upper: 0.45),
            v: try ScalarInterval(lower: 0.35, upper: 0.55)
        )

        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
            of: surface,
            over: parameterBox,
            tolerance: tolerance
        )

        for vIndex in 0..<7 {
            let v = 0.35 + 0.20 * Double(vIndex) / 6.0
            for uIndex in 0..<7 {
                let u = 0.25 + 0.20 * Double(uIndex) / 6.0
                let derivatives = try surface.parameterDerivatives(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
                #expect(enclosure.position.contains(derivatives.position))
                #expect(enclosure.tangentU.contains(derivatives.tangentU))
                #expect(enclosure.tangentV.contains(derivatives.tangentV))
                #expect(enclosure.secondDerivativeUU.contains(derivatives.secondDerivativeUU))
                #expect(enclosure.secondDerivativeUV.contains(derivatives.secondDerivativeUV))
                #expect(enclosure.secondDerivativeVV.contains(derivatives.secondDerivativeVV))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedOffsetProjectionRecoversItsUniqueParameter() throws {
        let projectionTolerance = ModelingTolerance(
            distance: 1.0e-6,
            angle: 1.0e-8,
            relative: 1.0e-9
        )
        let surface = Surface3D.procedural(.offset(OffsetSurface3D(
            source: .bSpline(makeCurvedSurface()),
            distance: 0.12
        )))
        let expectedU = 0.36
        let expectedV = 0.44
        let point = try surface.point(
            u: expectedU,
            v: expectedV,
            tolerance: projectionTolerance
        )

        let result = try surface.parameterProjectionResult(
            of: point,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: 64,
                maximumSubdivisionDepth: 20,
                maximumSubdivisionCells: 65_536,
                maximumCandidateCount: 256
            ),
            tolerance: projectionTolerance
        )

        guard case let .projected(projection) = result else {
            Issue.record("A point evaluated on the procedural surface must project back to it.")
            return
        }
        #expect(abs(projection.u - expectedU) <= 2.0e-6)
        #expect(abs(projection.v - expectedV) <= 2.0e-6)
        #expect(projection.residual <= projectionTolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedOffsetProjectionBalancesSubdivisionNearAParameterBoundary() throws {
        let projectionTolerance = ModelingTolerance(
            distance: 1.0e-6,
            angle: 1.0e-8,
            relative: 1.0e-9
        )
        let surface = Surface3D.procedural(.offset(OffsetSurface3D(
            source: .bSpline(makeCurvedSurface()),
            distance: 0.12
        )))
        let expectedU = 0.87
        let expectedV = 0.002
        let point = try surface.point(
            u: expectedU,
            v: expectedV,
            tolerance: projectionTolerance
        )

        let result = try surface.parameterProjectionResult(
            of: point,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: 64,
                maximumSubdivisionDepth: 24,
                maximumSubdivisionCells: 8_192,
                maximumCandidateCount: 256
            ),
            tolerance: projectionTolerance
        )

        guard case let .projected(projection) = result else {
            Issue.record("A boundary-adjacent point must retain a unique procedural parameter projection.")
            return
        }
        #expect(abs(projection.u - expectedU) <= 2.0e-6)
        #expect(abs(projection.v - expectedV) <= 2.0e-6)
        #expect(projection.residual <= projectionTolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func proceduralDifferentialGeometryMatchesEquivalentCylinder() throws {
        let procedural = Surface3D.procedural(.offset(OffsetSurface3D(
            source: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            distance: 0.5
        )))
        let expected = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.5
        ))

        let actualGeometry = try procedural.differentialGeometry(
            atU: 0.82,
            v: 0.34,
            tolerance: tolerance
        )
        let expectedGeometry = try expected.differentialGeometry(
            atU: 0.82,
            v: 0.34,
            tolerance: tolerance
        )

        expectApproximatelyEqual(actualGeometry.position, expectedGeometry.position)
        expectApproximatelyEqual(actualGeometry.normal, expectedGeometry.normal)
        #expect(abs(actualGeometry.meanCurvature - expectedGeometry.meanCurvature) <= 1.0e-9)
        #expect(abs(actualGeometry.gaussianCurvature - expectedGeometry.gaussianCurvature) <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedOffsetClosestProjectionFindsTheGlobalNormalFoot() throws {
        let projectionTolerance = ModelingTolerance(
            distance: 1.0e-6,
            angle: 1.0e-8,
            relative: 1.0e-9
        )
        let offset = OffsetSurface3D(
            source: .bSpline(makeCurvedSurface()),
            distance: 0.12
        )
        let surface = Surface3D.procedural(.offset(offset))
        let expectedU = 0.37
        let expectedV = 0.43
        let target = try surface.point(
            u: expectedU,
            v: expectedV,
            tolerance: projectionTolerance
        )
        let normal = try surface.normal(
            u: expectedU,
            v: expectedV,
            tolerance: projectionTolerance
        )
        let query = target + normal * 0.025

        let projection = try offset.closestParameterProjection(
            of: query,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: 64,
                maximumSubdivisionDepth: 24,
                maximumSubdivisionCells: 262_144,
                maximumCandidateCount: 512
            ),
            tolerance: projectionTolerance
        )

        #expect(abs(projection.u - expectedU) <= 2.0e-5)
        #expect(abs(projection.v - expectedV) <= 2.0e-5)
        #expect(projection.point.isApproximatelyEqual(to: target, tolerance: 2.0e-5))
        #expect(abs(projection.residual - 0.025) <= 2.0e-5)
    }

    @Test(.timeLimit(.minutes(1)))
    func regularityValidatorAcceptsRegularOffsetAndRejectsFocalSingularity() throws {
        let source = Surface3D.bSpline(makeParabolicCylinder())
        let parameters = SurfaceParameterBox(
            u: try ScalarInterval(lower: -0.2, upper: 0.2),
            v: try ScalarInterval(lower: 0.2, upper: 0.8)
        )
        let regular = Surface3D.procedural(.offset(OffsetSurface3D(
            source: source,
            distance: 0.2
        )))
        try DefaultSurfaceRegularityValidator().validate(
            regular,
            over: parameters,
            tolerance: tolerance
        )

        let singular = Surface3D.procedural(.offset(OffsetSurface3D(
            source: source,
            distance: 0.5
        )))
        do {
            try DefaultSurfaceRegularityValidator().validate(
                singular,
                over: parameters,
                tolerance: tolerance
            )
            Issue.record("A focal offset singularity must fail regularity certification.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularGeometry)
        }
    }

    private func makeCurvedSurface() -> BSplineSurface3D {
        let zValues: [[Double]] = [
            [0.0, 0.05, 0.20],
            [0.075, 0.18, 0.35],
            [0.30, 0.42, 0.65],
        ]
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: (0..<3).map { vIndex in
                (0..<3).map { uIndex in
                    Point3D(
                        x: Double(uIndex) * 0.5,
                        y: Double(vIndex) * 0.5,
                        z: zValues[vIndex][uIndex]
                    )
                }
            }
        )
    }

    private func makeParabolicCylinder() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.0, y: 0.0, z: 1.0),
                    Point3D(x: 0.0, y: 0.0, z: -1.0),
                    Point3D(x: 1.0, y: 0.0, z: 1.0),
                ],
                [
                    Point3D(x: -1.0, y: 1.0, z: 1.0),
                    Point3D(x: 0.0, y: 1.0, z: -1.0),
                    Point3D(x: 1.0, y: 1.0, z: 1.0),
                ],
            ]
        )
    }

    private func expectApproximatelyEqual(
        _ actual: SurfaceParameterThirdOrderDerivatives,
        _ expected: SurfaceParameterThirdOrderDerivatives
    ) {
        expectApproximatelyEqual(actual.position, expected.position)
        expectApproximatelyEqual(actual.tangentU, expected.tangentU)
        expectApproximatelyEqual(actual.tangentV, expected.tangentV)
        expectApproximatelyEqual(actual.secondDerivativeUU, expected.secondDerivativeUU)
        expectApproximatelyEqual(actual.secondDerivativeUV, expected.secondDerivativeUV)
        expectApproximatelyEqual(actual.secondDerivativeVV, expected.secondDerivativeVV)
        expectApproximatelyEqual(actual.thirdDerivativeUUU, expected.thirdDerivativeUUU)
        expectApproximatelyEqual(actual.thirdDerivativeUUV, expected.thirdDerivativeUUV)
        expectApproximatelyEqual(actual.thirdDerivativeUVV, expected.thirdDerivativeUVV)
        expectApproximatelyEqual(actual.thirdDerivativeVVV, expected.thirdDerivativeVVV)
    }

    private func expectApproximatelyEqual(
        _ actual: Point3D,
        _ expected: Point3D,
        accuracy: Double = 2.0e-8
    ) {
        #expect(abs(actual.x - expected.x) <= accuracy)
        #expect(abs(actual.y - expected.y) <= accuracy)
        #expect(abs(actual.z - expected.z) <= accuracy)
    }

    private func expectApproximatelyEqual(
        _ actual: Vector3D,
        _ expected: Vector3D,
        accuracy: Double = 2.0e-8
    ) {
        #expect(abs(actual.x - expected.x) <= accuracy)
        #expect(abs(actual.y - expected.y) <= accuracy)
        #expect(abs(actual.z - expected.z) <= accuracy)
    }
}
