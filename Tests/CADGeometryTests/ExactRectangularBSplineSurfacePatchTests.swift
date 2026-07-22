import Testing
import CADCore
@testable import CADGeometry

@Suite("Exact rectangular NURBS surface patches")
struct ExactRectangularBSplineSurfacePatchTests {
    @Test(
        .timeLimit(.minutes(1)),
        arguments: exactSurfaceCases
    )
    func preservesPositionNormalAndShapeOperator(
        surfaceCase: ExactPatchSurfaceCase
    ) throws {
        let patch = try ExactRectangularBSplineSurfacePatchBuilder().build(
            surface: surfaceCase.surface,
            lowerU: surfaceCase.lowerU,
            upperU: surfaceCase.upperU,
            lowerV: surfaceCase.lowerV,
            upperV: surfaceCase.upperV,
            tolerance: .standard
        )
        for uFraction in [0.0, 0.23, 0.5, 0.81, 1.0] {
            for vFraction in [0.0, 0.31, 0.67, 1.0] {
                let sourceParameter = SurfaceParameter(
                    u: surfaceCase.lowerU
                        + (surfaceCase.upperU - surfaceCase.lowerU) * uFraction,
                    v: surfaceCase.lowerV
                        + (surfaceCase.upperV - surfaceCase.lowerV) * vFraction
                )
                let patchParameter = try patch.parameter(
                    for: sourceParameter,
                    tolerance: .standard
                )
                let source = try surfaceCase.surface.differentialGeometry(
                    atU: sourceParameter.u,
                    v: sourceParameter.v,
                    tolerance: .standard
                )
                let converted = try patch.surface.differentialGeometry(
                    atU: patchParameter.u,
                    v: patchParameter.v,
                    tolerance: .standard
                )

                #expect((source.position - converted.position).length <= 1.0e-9)
                #expect(source.normal.dot(converted.normal) >= 1.0 - 1.0e-9)
                #expect(abs(
                    source.minimumPrincipalCurvature
                        - converted.minimumPrincipalCurvature
                ) <= 1.0e-8)
                #expect(abs(
                    source.maximumPrincipalCurvature
                        - converted.maximumPrincipalCurvature
                ) <= 1.0e-8)
            }
        }
    }

    private static let exactSurfaceCases: [ExactPatchSurfaceCase] = [
        ExactPatchSurfaceCase(
            name: "plane",
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            lowerU: -0.8,
            upperU: 1.2,
            lowerV: -0.6,
            upperV: 0.7
        ),
        ExactPatchSurfaceCase(
            name: "cylinder",
            surface: .cylinder(Cylinder3D(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            lowerU: 0.2,
            upperU: 2.4,
            lowerV: -0.6,
            upperV: 0.7
        ),
        ExactPatchSurfaceCase(
            name: "analyticPlane",
            surface: .analytic(.plane(origin: .origin, normal: .unitZ)),
            lowerU: -0.8,
            upperU: 1.2,
            lowerV: -0.6,
            upperV: 0.7
        ),
        ExactPatchSurfaceCase(
            name: "analyticCylinder",
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            lowerU: 0.2,
            upperU: 2.4,
            lowerV: -0.6,
            upperV: 0.7
        ),
        ExactPatchSurfaceCase(
            name: "cone",
            surface: .analytic(.cone(
                apex: .origin,
                axis: .unitZ,
                halfAngle: 0.4
            )),
            lowerU: 0.2,
            upperU: 2.4,
            lowerV: 1.0,
            upperV: 2.0
        ),
        ExactPatchSurfaceCase(
            name: "sphere",
            surface: .analytic(.sphere(center: .origin, radius: 2.0)),
            lowerU: 0.2,
            upperU: 2.4,
            lowerV: -0.6,
            upperV: 0.7
        ),
        ExactPatchSurfaceCase(
            name: "torus",
            surface: .analytic(.torus(
                center: .origin,
                axis: .unitZ,
                majorRadius: 3.0,
                minorRadius: 0.5
            )),
            lowerU: 0.2,
            upperU: 2.4,
            lowerV: -0.6,
            upperV: 0.7
        ),
        ExactPatchSurfaceCase(
            name: "rationalBSpline",
            surface: .bSpline(BSplineSurface3D(
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
                        Point3D(x: 0.0, y: 1.0, z: 0.1),
                        Point3D(x: 1.0, y: 1.0, z: 0.4),
                    ],
                ],
                weights: [
                    [1.0, 0.8],
                    [1.2, 1.0],
                ]
            )),
            lowerU: 0.0,
            upperU: 1.0,
            lowerV: 0.0,
            upperV: 1.0
        ),
    ]
}

struct ExactPatchSurfaceCase: CustomTestStringConvertible, Sendable {
    let name: String
    let surface: Surface3D
    let lowerU: Double
    let upperU: Double
    let lowerV: Double
    let upperV: Double

    var testDescription: String { name }
}
