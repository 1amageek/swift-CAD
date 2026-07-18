import CADCore
@testable import CADGeometry
import Testing

@Suite("Bounded B-Spline Surface Intersection")
struct BoundedBSplineSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func transverseBilinearSurfacesProduceVerifiedCurveAndDualPcurves() throws {
        let horizontal = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ]
        )
        let vertical = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.5, z: -1.0), Point3D(x: 1.0, y: 0.5, z: -1.0)],
                [Point3D(x: 0.0, y: 0.5, z: 1.0), Point3D(x: 1.0, y: 0.5, z: 1.0)],
            ],
            weights: [
                [1.0, 1.25],
                [0.75, 1.0],
            ]
        )
        let first = Surface3D.bSpline(horizontal)
        let second = Surface3D.bSpline(vertical)

        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        guard case let .curve(result) = try #require(intersections.first),
              case .bSpline = result.curve else {
            Issue.record("Two transverse bounded B-spline surfaces must produce a bounded curve.")
            return
        }
        #expect(intersections.count == 1)
        #expect(result.kind == .transverse)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: first, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: second, tolerance: tolerance)

        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let firstUV = try result.firstSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let secondUV = try result.secondSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let firstPoint = try first.point(u: firstUV.u, v: firstUV.v, tolerance: tolerance)
            let secondPoint = try second.point(u: secondUV.u, v: secondUV.v, tolerance: tolerance)
            #expect(firstPoint.isApproximatelyEqual(to: secondPoint, tolerance: tolerance.distance))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func identicalSurfacesProduceCoincidence() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ]
        )
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(surface),
            second: .bSpline(surface),
            tolerance: tolerance
        )
        #expect(intersections.count == 1)
        #expect(intersections.contains { if case .coincident = $0 { return true }; return false })
    }
}
