import CADCore
@testable import CADGeometry
import Testing

@Suite("Surface-lift bounding boxes")
struct SurfaceLiftBoundingBoxTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func certifiedIntersectionTruthBoundsEveryTrimmedPoint() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 3.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )
        let interval = try ScalarInterval(lower: 0.125, upper: 0.875)
        var checkedCurveCount = 0
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .surfaceLift(lift) = result.curve else {
                continue
            }
            let bounds = try lift.boundingBox(
                over: interval,
                tolerance: tolerance
            )
            for index in 0...128 {
                let fraction = interval.lower
                    + interval.width * Double(index) / 128.0
                let point = try lift.point(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                #expect(bounds.contains(point, tolerance: tolerance.distance))
            }
            checkedCurveCount += 1
        }
        #expect(checkedCurveCount == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticSupportUsesCertifiedDerivativeEnclosure() throws {
        let surface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let lift = SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: .harmonic(
                center: Point2D(x: 0.0, y: 0.0),
                cosine: Point2D(x: 0.5, y: 0.0),
                sine: Point2D(x: 0.0, y: 0.75),
                startParameter: 0.0,
                endParameter: Double.pi * 2.0
            )
        )
        let interval = try ScalarInterval(lower: 0.2, upper: 0.8)
        let bounds = try lift.boundingBox(
            over: interval,
            tolerance: tolerance
        )

        for index in 0...256 {
            let fraction = interval.lower
                + interval.width * Double(index) / 256.0
            let point = try lift.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            #expect(bounds.contains(point, tolerance: tolerance.distance))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func proceduralSupportUsesLocalizedParameterEnclosure() throws {
        let surface = Surface3D.procedural(.offset(OffsetSurface3D(
            source: .bSpline(BSplineSurface3D(
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
            )),
            distance: 0.2
        )))
        let lift = SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: .affine(
                origin: Point2D(x: -0.4, y: 0.2),
                direction: Point2D(x: 0.8, y: 0.6),
                startParameter: 0.0,
                endParameter: 1.0
            )
        )
        let interval = try ScalarInterval(lower: 0.25, upper: 0.75)
        let bounds = try lift.boundingBox(
            over: interval,
            tolerance: tolerance
        )

        for index in 0...128 {
            let fraction = interval.lower
                + interval.width * Double(index) / 128.0
            let point = try lift.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            #expect(bounds.contains(point, tolerance: 0.0))
        }
        #expect(bounds.size.y <= 0.300_001)
    }
}
