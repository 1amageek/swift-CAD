import Foundation
import CADCore

struct CoaxialSphereTorusSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        sphere: CanonicalAnalyticSurface.Sphere,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let centerOffset = sphere.center - torus.center
        let axialDistance = centerOffset.dot(torus.axis)
        let radialOffset = centerOffset - torus.axis * axialDistance
        guard radialOffset.length <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: radialOffset.length,
                tolerance: tolerance,
                message: "Sphere-torus intersection requires the sphere center on the torus axis."
            )
        }

        let meridian = try MeridianCircleIntersector().intersections(
            firstCenter: .init(radius: torus.majorRadius, axis: 0.0),
            firstRadius: torus.minorRadius,
            secondCenter: .init(radius: 0.0, axis: axialDistance),
            secondRadius: sphere.radius,
            tolerance: tolerance
        )

        var results: [SurfaceSurfaceIntersection] = []
        for candidate in meridian.points {
            guard candidate.radius >= -tolerance.distance else {
                continue
            }
            let center = torus.center + torus.axis * candidate.axis
            if candidate.radius <= tolerance.distance {
                results.append(try verifier.point(
                    center,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                ))
                continue
            }
            results.append(try verifier.curve(
                .circle(Circle3D(
                    center: center,
                    normal: torus.axis,
                    radius: candidate.radius
                )),
                kind: meridian.isTangent ? .tangent : .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            ))
        }
        return results
    }
}
