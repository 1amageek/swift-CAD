import CADCore
@testable import CADGeometry
@testable import CADTopology
import Testing

@Suite("Trimmed analytic surface volume")
struct TrimmedAnalyticSurfaceVolumeEvaluatorTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func sphericalRectangleBoundsContainClosedFormVolume() throws {
        let radius = 2.5
        let boundsResult = try TrimmedAnalyticSurfaceVolumeEvaluator().faceVolumeBounds(
            surface: .analytic(.sphere(center: .origin, radius: radius)),
            domain: ExactRectangularPcurveDomain(
                uLower: 0.0,
                uUpper: 2.0 * Double.pi,
                vLower: -Double.pi * 0.5,
                vUpper: Double.pi * 0.5
            ),
            reference: .origin,
            tolerance: tolerance
        )
        let bounds = try #require(boundsResult)
        let expected = 4.0 * Double.pi * radius * radius * radius / 3.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test
    func toroidalRectangleBoundsContainClosedFormVolume() throws {
        let majorRadius = 4.0
        let minorRadius = 1.25
        let boundsResult = try TrimmedAnalyticSurfaceVolumeEvaluator().faceVolumeBounds(
            surface: .analytic(.torus(
                center: .origin,
                axis: .unitZ,
                majorRadius: majorRadius,
                minorRadius: minorRadius
            )),
            domain: ExactRectangularPcurveDomain(
                uLower: 0.0,
                uUpper: 2.0 * Double.pi,
                vLower: 0.0,
                vUpper: 2.0 * Double.pi
            ),
            reference: .origin,
            tolerance: tolerance
        )
        let bounds = try #require(boundsResult)
        let expected = 2.0 * Double.pi * Double.pi
            * majorRadius * minorRadius * minorRadius

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test
    func cylindricalRectangleBoundsContainClosedFormSideContribution() throws {
        let radius = 2.0
        let height = 3.0
        let boundsResult = try TrimmedAnalyticSurfaceVolumeEvaluator().faceVolumeBounds(
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: radius
            )),
            domain: ExactRectangularPcurveDomain(
                uLower: 0.0,
                uUpper: 2.0 * Double.pi,
                vLower: 0.0,
                vUpper: height
            ),
            reference: .origin,
            tolerance: tolerance
        )
        let bounds = try #require(boundsResult)
        let expected = 2.0 * Double.pi * radius * radius * height / 3.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test
    func planarHarmonicLoopBoundsContainGreenTheoremVolumeForEitherTraversal() throws {
        let radius = 2.0
        let forward = SurfaceParameterCurve.harmonic(
            center: Point2D(x: 0.0, y: 0.0),
            cosine: Point2D(x: radius, y: 0.0),
            sine: Point2D(x: 0.0, y: radius),
            startParameter: 0.0,
            endParameter: 2.0 * Double.pi
        )
        let reversed = try forward.reversed(tolerance: tolerance)
        let surface = Surface3D.analytic(.plane(
            origin: Point3D(x: 0.0, y: 0.0, z: 3.0),
            normal: .unitZ
        ))
        let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()
        let expected = Double.pi * radius * radius

        for curve in [forward, reversed] {
            let result = try evaluator.planarLoopVolumeBounds(
                surface: surface,
                parameterCurves: [curve],
                role: .outer,
                reference: .origin,
                requestedAreaWidth: tolerance.distance,
                tolerance: tolerance
            )
            let bounds = try #require(result)
            #expect(bounds.lower <= expected)
            #expect(bounds.upper >= expected)
            #expect(bounds.errorRadius <= tolerance.distance)
        }
    }

    @Test
    func planarInnerLoopNegatesCertifiedArea() throws {
        let radius = 1.5
        let curve = SurfaceParameterCurve.harmonic(
            center: Point2D(x: 0.0, y: 0.0),
            cosine: Point2D(x: radius, y: 0.0),
            sine: Point2D(x: 0.0, y: radius),
            startParameter: 0.0,
            endParameter: 2.0 * Double.pi
        )
        let result = try TrimmedAnalyticSurfaceVolumeEvaluator().planarLoopVolumeBounds(
            surface: .analytic(.plane(
                origin: Point3D(x: 0.0, y: 0.0, z: 3.0),
                normal: .unitZ
            )),
            parameterCurves: [curve],
            role: .inner,
            reference: .origin,
            requestedAreaWidth: tolerance.distance,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let expected = -Double.pi * radius * radius

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test
    func planarDegenerateLoopFailsTypedInsteadOfReturningZeroVolume() throws {
        do {
            _ = try TrimmedAnalyticSurfaceVolumeEvaluator().planarLoopVolumeBounds(
                surface: .analytic(.plane(
                    origin: Point3D(x: 0.0, y: 0.0, z: 3.0),
                    normal: .unitZ
                )),
                parameterCurves: [
                    .constantV(v: 0.0, uStart: -1.0, uEnd: 1.0),
                    .constantV(v: 0.0, uStart: 1.0, uEnd: -1.0),
                ],
                role: .outer,
                reference: .origin,
                requestedAreaWidth: tolerance.distance,
                tolerance: tolerance
            )
            Issue.record("Expected a typed topology failure for a zero-area pcurve loop.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .topologyFailure)
        }
    }

    @Test
    func concaveCoordinateLoopsMatchRectangularDecompositionOnCurvedSurfaces() throws {
        let uLower = 0.1
        let uMiddle = 0.6
        let uUpper = 1.2
        let vLower = 0.1
        let vMiddle = 0.4
        let vUpper = 0.8
        let loop = coordinateLLoop(
            uLower: uLower,
            uMiddle: uMiddle,
            uUpper: uUpper,
            vLower: vLower,
            vMiddle: vMiddle,
            vUpper: vUpper
        )
        let reference = Point3D(x: -0.3, y: 0.2, z: 0.1)
        let surfaces: [Surface3D] = [
            .analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 2.0)),
            .analytic(.cone(apex: .origin, axis: .unitZ, halfAngle: 0.5)),
            .analytic(.sphere(center: .origin, radius: 2.0)),
            .analytic(.torus(
                center: .origin,
                axis: .unitZ,
                majorRadius: 3.0,
                minorRadius: 0.75
            )),
        ]
        let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()

        for surface in surfaces {
            let coordinateResult = try evaluator.coordinateLoopVolumeBounds(
                surface: surface,
                parameterCurves: loop,
                role: .outer,
                reference: reference,
                tolerance: tolerance
            )
            let coordinate = try #require(coordinateResult)
            let lowerRectangleResult = try evaluator.faceVolumeBounds(
                surface: surface,
                domain: ExactRectangularPcurveDomain(
                    uLower: uLower,
                    uUpper: uUpper,
                    vLower: vLower,
                    vUpper: vMiddle
                ),
                reference: reference,
                tolerance: tolerance
            )
            let upperRectangleResult = try evaluator.faceVolumeBounds(
                surface: surface,
                domain: ExactRectangularPcurveDomain(
                    uLower: uLower,
                    uUpper: uMiddle,
                    vLower: vMiddle,
                    vUpper: vUpper
                ),
                reference: reference,
                tolerance: tolerance
            )
            let lowerRectangle = try #require(lowerRectangleResult)
            let upperRectangle = try #require(upperRectangleResult)
            let expectedLower = lowerRectangle.lower + upperRectangle.lower
            let expectedUpper = lowerRectangle.upper + upperRectangle.upper

            #expect(coordinate.lower <= expectedUpper)
            #expect(coordinate.upper >= expectedLower)
            #expect(abs(
                coordinate.midpoint
                    - (lowerRectangle.midpoint + upperRectangle.midpoint)
            ) <= tolerance.distance)
        }
    }

    @Test
    func torusCoordinateLoopCrossingAzimuthSeamMatchesUnwrappedRectangle() throws {
        let period = 2.0 * Double.pi
        let uLower = period - 0.2
        let uUpper = period + 0.3
        let vLower = 0.1
        let vUpper = 0.6
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 0.75
        ))
        let reference = Point3D(x: -0.3, y: 0.2, z: 0.1)
        let seamCrossingLoop: [SurfaceParameterCurve] = [
            .constantV(v: vLower, uStart: uLower, uEnd: period),
            .constantV(v: vLower, uStart: 0.0, uEnd: uUpper - period),
            .constantU(u: uUpper - period, vStart: vLower, vEnd: vUpper),
            .constantV(v: vUpper, uStart: uUpper - period, uEnd: 0.0),
            .constantV(v: vUpper, uStart: period, uEnd: uLower),
            .constantU(u: uLower, vStart: vUpper, vEnd: vLower),
        ]
        let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()

        let seamResult = try evaluator.coordinateLoopVolumeBounds(
            surface: surface,
            parameterCurves: seamCrossingLoop,
            role: .outer,
            reference: reference,
            tolerance: tolerance
        )
        let rectangleResult = try evaluator.faceVolumeBounds(
            surface: surface,
            domain: ExactRectangularPcurveDomain(
                uLower: uLower,
                uUpper: uUpper,
                vLower: vLower,
                vUpper: vUpper
            ),
            reference: reference,
            tolerance: tolerance
        )
        let seam = try #require(seamResult)
        let rectangle = try #require(rectangleResult)

        #expect(seam.lower <= rectangle.upper)
        #expect(seam.upper >= rectangle.lower)
        #expect(abs(seam.midpoint - rectangle.midpoint) <= tolerance.distance)
    }

    @Test
    func reversedCoordinateLoopPreservesCanonicalOuterContribution() throws {
        let forward = coordinateLLoop(
            uLower: 0.0,
            uMiddle: 1.0,
            uUpper: 2.0,
            vLower: 0.0,
            vMiddle: 1.0,
            vUpper: 3.0
        )
        let reversed = try forward.reversed().map {
            try $0.reversed(tolerance: tolerance)
        }
        let surface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()
        let expected = 16.0 / 3.0

        for loop in [forward, reversed] {
            let result = try evaluator.coordinateLoopVolumeBounds(
                surface: surface,
                parameterCurves: loop,
                role: .outer,
                reference: .origin,
                tolerance: tolerance
            )
            let bounds = try #require(result)
            #expect(bounds.lower <= expected)
            #expect(bounds.upper >= expected)
            #expect(bounds.errorRadius <= tolerance.distance)
        }
    }

    @Test
    func affineDiagonalTrimReturnsCertifiedCylinderContribution() throws {
        let loop: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            .affine(
                origin: Point2D(x: 1.0, y: 1.0),
                direction: Point2D(x: -1.0, y: -1.0),
                startParameter: 0.0,
                endParameter: 1.0
            ),
        ]
        let result = try TrimmedAnalyticSurfaceVolumeEvaluator().analyticLoopVolumeBounds(
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            parameterCurves: loop,
            role: .outer,
            reference: .origin,
            requestedWidth: tolerance.distance,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let expected = 2.0 / 3.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test
    func harmonicTrimReturnsCertifiedCylinderContribution() throws {
        let uRadius = 0.5
        let vRadius = 0.25
        let loop = SurfaceParameterCurve.harmonic(
            center: Point2D(x: 1.0, y: 1.0),
            cosine: Point2D(x: uRadius, y: 0.0),
            sine: Point2D(x: 0.0, y: vRadius),
            startParameter: 0.0,
            endParameter: 2.0 * Double.pi
        )
        let result = try TrimmedAnalyticSurfaceVolumeEvaluator().analyticLoopVolumeBounds(
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            parameterCurves: [loop],
            role: .outer,
            reference: .origin,
            requestedWidth: tolerance.distance,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let expected = 4.0 / 3.0 * Double.pi * uRadius * vRadius

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test
    func rationalBSplineTrimReturnsCertifiedCylinderContribution() throws {
        let diagonal = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.0, y: 1.0),
                Point2D(x: 0.5, y: 0.5),
                Point2D(x: 0.0, y: 0.0),
            ],
            weights: [1.0, 0.7, 1.0]
        )
        let result = try TrimmedAnalyticSurfaceVolumeEvaluator().analyticLoopVolumeBounds(
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            parameterCurves: [
                .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
                .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
                .bSpline(diagonal),
            ],
            role: .outer,
            reference: .origin,
            requestedWidth: tolerance.distance,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let expected = 2.0 / 3.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test
    func polynomialBSplineCylinderFluxMatchesAffineRepresentation() throws {
        let polynomialDiagonal = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.0, y: 1.0),
                Point2D(x: 0.5, y: 0.5),
                Point2D(x: 0.0, y: 0.0),
            ]
        )
        let commonEdges: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
        ]
        let affineLoop = commonEdges + [
            .affine(
                origin: Point2D(x: 1.0, y: 1.0),
                direction: Point2D(x: -1.0, y: -1.0),
                startParameter: 0.0,
                endParameter: 1.0
            ),
        ]
        let polynomialLoop = commonEdges + [.bSpline(polynomialDiagonal)]
        let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()
        let surface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let reference = Point3D(x: 0.3, y: -0.2, z: 0.4)
        let affine = try #require(try evaluator.analyticLoopVolumeBounds(
            surface: surface,
            parameterCurves: affineLoop,
            role: .outer,
            reference: reference,
            requestedWidth: tolerance.distance,
            tolerance: tolerance
        ))
        let polynomial = try #require(try evaluator.analyticLoopVolumeBounds(
            surface: surface,
            parameterCurves: polynomialLoop,
            role: .outer,
            reference: reference,
            requestedWidth: tolerance.distance,
            tolerance: tolerance
        ))

        #expect(polynomial.lower <= affine.upper)
        #expect(polynomial.upper >= affine.lower)
        #expect(abs(polynomial.midpoint - affine.midpoint) <= tolerance.distance)
    }

    @Test
    func nonClampedRationalBSplineTrimReturnsCertifiedCylinderContribution() throws {
        let diagonal = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 1.0, 2.0, 3.0, 4.0, 5.0],
            controlPoints: [
                Point2D(x: 2.0, y: 2.0),
                Point2D(x: 1.0, y: 1.0),
                Point2D(x: 0.0, y: 0.0),
            ],
            weights: [1.0, 0.8, 1.0]
        )
        let start = try diagonal.point(at: 2.0, tolerance: tolerance)
        let end = try diagonal.point(at: 3.0, tolerance: tolerance)
        let result = try TrimmedAnalyticSurfaceVolumeEvaluator().analyticLoopVolumeBounds(
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            parameterCurves: [
                .constantV(v: end.y, uStart: end.x, uEnd: start.x),
                .constantU(u: start.x, vStart: end.y, vEnd: start.y),
                .bSpline(diagonal),
            ],
            role: .outer,
            reference: .origin,
            requestedWidth: tolerance.distance,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let delta = start.x - end.x
        let expected = 4.0 / 3.0 * delta * delta * 0.5

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test
    func sphericalGreatCircleMeridianMatchesRectangularSphereContribution() throws {
        let uLower = 0.0
        let uUpper = 1.0
        let vLower = -0.5
        let vUpper = 0.5
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()
        let result = try evaluator.analyticLoopVolumeBounds(
            surface: surface,
            parameterCurves: [
                .constantV(v: vLower, uStart: uLower, uEnd: uUpper),
                .constantU(u: uUpper, vStart: vLower, vEnd: vUpper),
                .constantV(v: vUpper, uStart: uUpper, uEnd: uLower),
                .sphericalGreatCircle(
                    cosine: Vector3D(x: 0.0, y: 1.0, z: 0.0),
                    sine: Vector3D(x: 0.0, y: 0.0, z: 1.0),
                    startParameter: vUpper,
                    endParameter: vLower
                ),
            ],
            role: .outer,
            reference: .origin,
            requestedWidth: tolerance.distance,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let rectangleResult = try evaluator.faceVolumeBounds(
            surface: surface,
            domain: ExactRectangularPcurveDomain(
                uLower: uLower,
                uUpper: uUpper,
                vLower: vLower,
                vUpper: vUpper
            ),
            reference: .origin,
            tolerance: tolerance
        )
        let rectangle = try #require(rectangleResult)

        #expect(bounds.lower <= rectangle.upper)
        #expect(bounds.upper >= rectangle.lower)
        #expect(abs(bounds.midpoint - rectangle.midpoint) <= tolerance.distance)
    }

    @Test
    func sphericalGreatCircleEquatorMatchesRectangularSphereContribution() throws {
        let uLower = 0.0
        let uUpper = 1.0
        let vLower = 0.0
        let vUpper = 0.5
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()
        let result = try evaluator.analyticLoopVolumeBounds(
            surface: surface,
            parameterCurves: [
                .sphericalGreatCircle(
                    cosine: Vector3D(x: 0.0, y: 1.0, z: 0.0),
                    sine: Vector3D(x: -1.0, y: 0.0, z: 0.0),
                    startParameter: uLower,
                    endParameter: uUpper
                ),
                .constantU(u: uUpper, vStart: vLower, vEnd: vUpper),
                .constantV(v: vUpper, uStart: uUpper, uEnd: uLower),
                .constantU(u: uLower, vStart: vUpper, vEnd: vLower),
            ],
            role: .outer,
            reference: .origin,
            requestedWidth: tolerance.distance,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let rectangleResult = try evaluator.faceVolumeBounds(
            surface: surface,
            domain: ExactRectangularPcurveDomain(
                uLower: uLower,
                uUpper: uUpper,
                vLower: vLower,
                vUpper: vUpper
            ),
            reference: .origin,
            tolerance: tolerance
        )
        let rectangle = try #require(rectangleResult)

        #expect(bounds.lower <= rectangle.upper)
        #expect(bounds.upper >= rectangle.lower)
        #expect(abs(bounds.midpoint - rectangle.midpoint) <= tolerance.distance)
    }

    @Test
    func certifiedAnalyticImplicitTrimMatchesCylinderRectangle() throws {
        let cylinder = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let lowerHeight = -0.49
        let upperHeight = 0.49
        let implicitEdge = try certifiedCylinderGenerator(
            cylinder: cylinder,
            lowerHeight: lowerHeight,
            upperHeight: upperHeight
        )
        let uLower = try implicitEdge.startParameter(tolerance: tolerance).u
        let uUpper = uLower + 0.5
        let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()
        let result = try evaluator.analyticLoopVolumeBounds(
            surface: cylinder,
            parameterCurves: [
                .constantV(v: lowerHeight, uStart: uLower, uEnd: uUpper),
                .constantU(u: uUpper, vStart: lowerHeight, vEnd: upperHeight),
                .constantV(v: upperHeight, uStart: uUpper, uEnd: uLower),
                implicitEdge,
            ],
            role: .outer,
            reference: .origin,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let rectangleResult = try evaluator.faceVolumeBounds(
            surface: cylinder,
            domain: ExactRectangularPcurveDomain(
                uLower: uLower,
                uUpper: uUpper,
                vLower: lowerHeight,
                vUpper: upperHeight
            ),
            reference: .origin,
            tolerance: tolerance
        )
        let rectangle = try #require(rectangleResult)

        #expect(bounds.lower <= rectangle.upper)
        #expect(bounds.upper >= rectangle.lower)
        #expect(bounds.errorRadius <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticLoopNeverRelaxesItsRequestedEnclosure() throws {
        let cylinder = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let lowerHeight = -0.49
        let upperHeight = 0.49
        let implicitEdge = try certifiedCylinderGenerator(
            cylinder: cylinder,
            lowerHeight: lowerHeight,
            upperHeight: upperHeight
        )
        let uLower = try implicitEdge.startParameter(tolerance: tolerance).u
        let uUpper = uLower + 0.5
        let requestedWidth = tolerance.distance * 0.01

        do {
            let result = try TrimmedAnalyticSurfaceVolumeEvaluator()
                .analyticLoopVolumeBounds(
                    surface: cylinder,
                    parameterCurves: [
                        .constantV(v: lowerHeight, uStart: uLower, uEnd: uUpper),
                        .constantU(u: uUpper, vStart: lowerHeight, vEnd: upperHeight),
                        .constantV(v: upperHeight, uStart: uUpper, uEnd: uLower),
                        implicitEdge,
                    ],
                    role: .outer,
                    reference: .origin,
                    requestedWidth: requestedWidth,
                    tolerance: tolerance
            )
            let bounds = try #require(result)
            #expect(bounds.upper - bounds.lower <= requestedWidth)
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    private func certifiedCylinderGenerator(
        cylinder: Surface3D,
        lowerHeight: Double,
        upperHeight: Double
    ) throws -> SurfaceParameterCurve {
        func plane(radial: Vector3D) -> BSplineSurface3D {
            BSplineSurface3D(
                uDegree: 1,
                vDegree: 1,
                uKnots: [0.0, 0.0, 1.0, 1.0],
                vKnots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    [
                        Point3D.origin + radial * 0.5 + Vector3D.unitZ * -0.5,
                        Point3D.origin + radial * 1.5 + Vector3D.unitZ * -0.5,
                    ],
                    [
                        Point3D.origin + radial * 0.5 + Vector3D.unitZ * 0.5,
                        Point3D.origin + radial * 1.5 + Vector3D.unitZ * 0.5,
                    ],
                ],
                weights: [[1.0, 1.0], [1.0, 1.0]]
            )
        }
        let referencePlane = plane(radial: .unitX)
        let analyticNURBS = try AnalyticSurfaceBSplineBuilder().surface(
            for: CanonicalAnalyticSurface(cylinder),
            boundedBy: referencePlane,
            periodicSeamOffset: 0.0,
            tolerance: tolerance
        )
        let generatorPoint = try analyticNURBS.point(
            u: 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        let radial = try Vector3D(
            x: generatorPoint.x,
            y: generatorPoint.y,
            z: 0.0
        ).normalized(tolerance: tolerance.distance)
        let boundedPlane = plane(radial: radial)
        func parameters(at height: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: height),
                second: SurfaceParameter(u: 0.5, v: height + 0.5)
            )
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: lowerHeight, upper: upperHeight),
                secondU: try ScalarInterval(lower: 0.49, upper: 0.51),
                secondV: try ScalarInterval(lower: 0.0, upper: 1.0)
            ),
            freeParameter: .firstV,
            direction: .forward,
            lowerAnchor: try parameters(at: lowerHeight),
            midpointAnchor: try parameters(at: 0.0),
            upperAnchor: try parameters(at: upperHeight),
            firstSurface: analyticNURBS,
            secondSurface: boundedPlane,
            tolerance: tolerance
        )
        let implicit = try CertifiedImplicitIntersectionCurve(
            firstSurface: analyticNURBS,
            secondSurface: boundedPlane,
            cells: [cell],
            isClosed: false,
            tolerance: tolerance
        )
        let intersection = try CertifiedAnalyticBSplineIntersectionCurve(
            implicitCurve: implicit,
            analyticSurface: cylinder,
            analyticIsFirst: true,
            periodicSeamOffset: 0.0,
            tolerance: tolerance
        )
        return .certifiedAnalyticImplicit(
            try CertifiedAnalyticImplicitSurfaceParameterCurve(
                intersection: intersection,
                startFraction: 1.0,
                endFraction: 0.0,
                tolerance: tolerance
            )
        )
    }

    private func coordinateLLoop(
        uLower: Double,
        uMiddle: Double,
        uUpper: Double,
        vLower: Double,
        vMiddle: Double,
        vUpper: Double
    ) -> [SurfaceParameterCurve] {
        [
            .constantV(v: vLower, uStart: uLower, uEnd: uUpper),
            .constantU(u: uUpper, vStart: vLower, vEnd: vMiddle),
            .constantV(v: vMiddle, uStart: uUpper, uEnd: uMiddle),
            .constantU(u: uMiddle, vStart: vMiddle, vEnd: vUpper),
            .constantV(v: vUpper, uStart: uMiddle, uEnd: uLower),
            .constantU(u: uLower, vStart: vUpper, vEnd: vLower),
        ]
    }
}
