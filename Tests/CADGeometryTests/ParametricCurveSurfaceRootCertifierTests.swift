import CADCore
import Testing
@testable import CADGeometry

@Suite("Parametric curve-surface root certifier")
struct ParametricCurveSurfaceRootCertifierTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-8,
        relative: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func proceduralRootOnSharedCellBoundariesIsNotExcluded() throws {
        let surface = Surface3D.procedural(.offset(OffsetSurface3D(
            source: .bSpline(makeParabolicCylinder()),
            distance: 0.2
        )))
        let target = try surface.point(
            u: 0.0,
            v: 0.5,
            tolerance: tolerance
        )
        let normal = try surface.normal(
            u: 0.0,
            v: 0.5,
            tolerance: tolerance
        )
        let curve = Curve3D.line(Line3D(
            origin: target + normal * 0.1,
            direction: -normal
        ))
        let curvePoint = try curve.point(at: 0.1, tolerance: tolerance)
        let witness = try CurveSurfaceIntersection(
            point: target,
            curveParameter: 0.1,
            surfaceU: 0.0,
            surfaceV: 0.5,
            kind: .transverse,
            residual: (curvePoint - target).length,
            iterations: 1
        )
        let certifier = DefaultParametricCurveSurfaceRootCertifier()
        let curveIntervals = [
            try ScalarInterval(lower: 0.08, upper: 0.1),
            try ScalarInterval(lower: 0.1, upper: 0.12),
        ]
        let uIntervals = [
            try ScalarInterval(lower: -0.02, upper: 0.0),
            try ScalarInterval(lower: 0.0, upper: 0.02),
        ]
        let vIntervals = [
            try ScalarInterval(lower: 0.48, upper: 0.5),
            try ScalarInterval(lower: 0.5, upper: 0.52),
        ]

        for curveInterval in curveIntervals {
            for uInterval in uIntervals {
                for vInterval in vIntervals {
                    let cell = ParametricCurveSurfaceRootCell(
                        curve: curveInterval,
                        surfaceU: uInterval,
                        surfaceV: vInterval,
                        surfacePatches: []
                    )
                    let certificate = try certifier.certificate(
                        curve: curve,
                        surface: surface,
                        cell: cell,
                        tolerance: tolerance
                    )
                    if case .excluded = certificate {
                        Issue.record(
                            "A cell sharing the procedural root boundary was excluded."
                        )
                    }
                    let boundaryCertificate = try certifier.boundaryCertificate(
                        curve: curve,
                        surface: surface,
                        cell: cell,
                        witness: witness,
                        tolerance: tolerance
                    )
                    if case .unique = boundaryCertificate {
                        continue
                    }
                    Issue.record(
                        "A transverse procedural boundary root was not certified unique."
                    )
                }
            }
        }
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
}
