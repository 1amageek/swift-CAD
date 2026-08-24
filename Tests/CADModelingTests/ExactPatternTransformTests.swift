import Testing
import CADCore
import CADGeometry
@testable import CADModeling

@Suite("Exact pattern isometry")
struct ExactPatternTransformTests {
    @Test(.timeLimit(.minutes(1)))
    func preservesCurveParametersAcrossRotationAndReflection() throws {
        let tolerance = ModelingTolerance.standard
        let curves: [(curve: Curve3D, parameter: Double)] = [
            (
                .line(Line3D(origin: .origin, direction: .unitX)),
                0.35
            ),
            (
                .circle(Circle3D(
                    center: Point3D(x: 0.2, y: -0.1, z: 0.3),
                    normal: .unitZ,
                    radius: 0.4
                )),
                0.7
            ),
            (
                .analytic(.circle(
                    center: Point3D(x: -0.1, y: 0.3, z: 0.2),
                    normal: .unitY,
                    radius: 0.25
                )),
                1.1
            ),
            (
                .analytic(.arc(
                    center: Point3D(x: 0.2, y: 0.1, z: -0.3),
                    normal: .unitX,
                    radius: 0.5,
                    startAngle: 0.2,
                    endAngle: 1.8
                )),
                0.9
            ),
            (
                .analytic(.ellipse(
                    center: Point3D(x: 0.1, y: 0.2, z: 0.3),
                    normal: .unitZ,
                    majorAxis: .unitX,
                    majorRadius: 0.6,
                    minorRadius: 0.2
                )),
                2.2
            ),
            (
                .analytic(.hyperbola(Hyperbola3D(
                    center: Point3D(x: 0.1, y: 0.2, z: 0.3),
                    normal: .unitZ,
                    transverseAxis: .unitX,
                    transverseRadius: 0.4,
                    conjugateRadius: 0.2
                ))),
                0.45
            ),
            (
                .analytic(.parabola(Parabola3D(
                    vertex: Point3D(x: -0.2, y: 0.1, z: 0.4),
                    normal: .unitZ,
                    axis: .unitX,
                    focalLength: 0.3
                ))),
                0.25
            ),
            (
                .bSpline(BSplineCurve3D(
                    degree: 2,
                    knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                    controlPoints: [
                        .origin,
                        Point3D(x: 0.4, y: 0.3, z: 0.2),
                        Point3D(x: 0.8, y: -0.1, z: 0.5),
                    ],
                    weights: [1.0, 0.8, 1.0]
                )),
                0.6
            ),
        ]
        let transforms = [
            try ExactPatternTransform.rotated(
                around: Point3D(x: 0.2, y: -0.4, z: 0.1),
                direction: Vector3D(x: 1.0, y: 2.0, z: -1.0),
                angle: 0.73,
                tolerance: tolerance
            ),
            try ExactPatternTransform.mirrored(
                across: Point3D(x: -0.3, y: 0.2, z: 0.1),
                normal: Vector3D(x: 1.0, y: -2.0, z: 0.5),
                tolerance: tolerance
            ),
        ]

        for transform in transforms {
            for sample in curves {
                let transformed = try transform.applying(
                    to: sample.curve,
                    from: sample.parameter - 0.1,
                    to: sample.parameter + 0.1,
                    tolerance: tolerance
                )
                let expected = transform.applying(to: try sample.curve.point(
                    at: sample.parameter,
                    tolerance: tolerance
                ))
                let actual = try transformed.point(
                    at: sample.parameter,
                    tolerance: tolerance
                )
                #expect((actual - expected).length <= 1.0e-12)
            }
        }
        #expect(transforms[0].reversesOrientation == false)
        #expect(transforms[1].reversesOrientation)
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesRationalSurfaceParametersAcrossRotationAndReflection() throws {
        let tolerance = ModelingTolerance.standard
        let source = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.2),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: -0.1),
                    Point3D(x: 1.0, y: 1.0, z: 0.4),
                ],
            ],
            weights: [
                [1.0, 0.8],
                [0.9, 1.0],
            ]
        )
        let transforms = [
            try ExactPatternTransform.rotated(
                around: Point3D(x: -0.1, y: 0.3, z: 0.2),
                direction: Vector3D(x: 1.0, y: -2.0, z: 0.5),
                angle: 0.61,
                tolerance: tolerance
            ),
            try ExactPatternTransform.mirrored(
                across: Point3D(x: 0.2, y: 0.0, z: -0.1),
                normal: Vector3D(x: 1.0, y: 1.0, z: 0.5),
                tolerance: tolerance
            ),
        ]

        for transform in transforms {
            let transformed = try transform.applying(
                to: source,
                tolerance: tolerance
            )
            for (u, v) in [(0.0, 0.0), (0.25, 0.7), (1.0, 1.0)] {
                let expected = transform.applying(to: try source.point(
                    u: u,
                    v: v,
                    tolerance: tolerance
                ))
                let actual = try transformed.point(
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
                #expect((actual - expected).length <= 1.0e-12)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func mapsAnalyticSurfacePcurvesToTheSameIsometricLocus() throws {
        let tolerance = ModelingTolerance.standard
        let transform = try ExactPatternTransform.mirrored(
            across: Point3D(x: 0.2, y: -0.1, z: 0.4),
            normal: Vector3D(x: 1.0, y: 2.0, z: -0.5),
            tolerance: tolerance
        )
        let samples: [(surface: Surface3D, parameters: [SurfaceParameter])] = [
            (
                .plane(Plane3D(origin: .origin, normal: .unitZ)),
                [SurfaceParameter(u: -0.2, v: 0.3), SurfaceParameter(u: 0.6, v: -0.4)]
            ),
            (
                .cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 0.5)),
                [SurfaceParameter(u: 0.3, v: -0.2), SurfaceParameter(u: 1.4, v: 0.7)]
            ),
            (
                .analytic(.cone(apex: .origin, axis: .unitY, halfAngle: 0.4)),
                [SurfaceParameter(u: 0.2, v: 0.5), SurfaceParameter(u: 1.1, v: 0.9)]
            ),
            (
                .analytic(.torus(
                    center: .origin,
                    axis: .unitX,
                    majorRadius: 0.8,
                    minorRadius: 0.2
                )),
                [SurfaceParameter(u: 0.5, v: 0.2), SurfaceParameter(u: 1.7, v: 1.1)]
            ),
        ]

        for sample in samples {
            let image = try ExactPatternSurfaceImage(
                source: sample.surface,
                transform: transform,
                tolerance: tolerance
            )
            let sourcePcurve = SurfaceParameterCurve.polyline(sample.parameters)
            let targetPcurve = try image.applying(to: sourcePcurve, tolerance: tolerance)
            for fraction in [0.0, 0.25, 0.75, 1.0] {
                let sourceParameter = try sourcePcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let targetParameter = try targetPcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let expected = transform.applying(to: try sample.surface.point(
                    u: sourceParameter.u,
                    v: sourceParameter.v,
                    tolerance: tolerance
                ))
                let actual = try image.surface.point(
                    u: targetParameter.u,
                    v: targetParameter.v,
                    tolerance: tolerance
                )
                #expect((actual - expected).length <= 1.0e-12)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func mapsSphericalGreatCirclePcurveThroughGeneralRotation() throws {
        let tolerance = ModelingTolerance.standard
        let source = Surface3D.analytic(.sphere(center: .origin, radius: 0.7))
        let transform = try ExactPatternTransform.rotated(
            around: Point3D(x: 0.1, y: 0.2, z: -0.3),
            direction: Vector3D(x: 1.0, y: -1.0, z: 2.0),
            angle: 0.83,
            tolerance: tolerance
        )
        let sourcePcurve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitY,
            sine: -Vector3D.unitX,
            startParameter: 0.2,
            endParameter: 1.3
        )
        let image = try ExactPatternSurfaceImage(
            source: source,
            transform: transform,
            tolerance: tolerance
        )
        let targetPcurve = try image.applying(to: sourcePcurve, tolerance: tolerance)

        for fraction in [0.0, 0.3, 0.8, 1.0] {
            let sourceParameter = try sourcePcurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let targetParameter = try targetPcurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let expected = transform.applying(to: try source.point(
                u: sourceParameter.u,
                v: sourceParameter.v,
                tolerance: tolerance
            ))
            let actual = try image.surface.point(
                u: targetParameter.u,
                v: targetParameter.v,
                tolerance: tolerance
            )
            #expect((actual - expected).length <= 1.0e-12)
        }
    }
}
