import Foundation
import CADCore

struct PlaneSphereSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        sphere: CanonicalAnalyticSurface.Sphere,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let signedDistance = (sphere.center - plane.origin).dot(plane.normal)
        let distance = abs(signedDistance)
        guard distance <= sphere.radius + tolerance.distance else { return [] }
        let center = sphere.center + plane.normal * -signedDistance
        let squaredRadius = max(0.0, sphere.radius * sphere.radius - distance * distance)
        if squaredRadius <= tolerance.distance * tolerance.distance {
            return [try verifier.point(
                center,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )]
        }
        return [try verifier.curve(
            .circle(Circle3D(
                center: center,
                normal: plane.normal,
                radius: sqrt(squaredRadius)
            )),
            kind: .transverse,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
            tolerance: tolerance
        )]
    }
}
