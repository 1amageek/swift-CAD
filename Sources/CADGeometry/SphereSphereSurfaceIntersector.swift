import Foundation
import CADCore

struct SphereSphereSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Sphere,
        second: CanonicalAnalyticSurface.Sphere,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let centerOffset = second.center - first.center
        let centerDistance = centerOffset.length
        if centerDistance <= tolerance.distance {
            let radiusResidual = abs(first.radius - second.radius)
            guard radiusResidual <= tolerance.distance else { return [] }
            return [.coincident(try SurfaceSurfaceCoincidence(
                residual: max(centerDistance, radiusResidual),
                tolerance: tolerance
            ))]
        }
        guard centerDistance <= first.radius + second.radius + tolerance.distance,
              centerDistance + min(first.radius, second.radius)
                >= max(first.radius, second.radius) - tolerance.distance else {
            return []
        }

        let direction = try centerOffset.normalized(tolerance: tolerance.distance)
        let axialDistance = (
            centerDistance * centerDistance
                + first.radius * first.radius
                - second.radius * second.radius
        ) / (2.0 * centerDistance)
        let center = first.center + direction * axialDistance
        let squaredRadius = max(0.0, first.radius * first.radius - axialDistance * axialDistance)
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
                normal: direction,
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
