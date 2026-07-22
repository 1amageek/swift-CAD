import Foundation
import CADCore

struct CoaxialConeCylinderSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        cone: CanonicalAnalyticSurface.Cone,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let radialOffset = AnalyticAxisRelation.radialOffset(
            from: cylinder.origin,
            axis: cylinder.axis,
            to: cone.apex
        )
        guard AnalyticAxisRelation.areParallel(cone.axis, cylinder.axis, tolerance: tolerance),
              radialOffset.length <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The coaxial cone-cylinder intersector requires coincident parallel axes."
            )
        }
        let height = cylinder.radius / tan(cone.halfAngle)
        return try [-1.0, 1.0].map { sign in
            try verifier.curve(
                .circle(Circle3D(
                    center: cone.apex + cone.axis * (sign * height),
                    normal: cone.axis,
                    radius: cylinder.radius
                )),
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )
        }
    }
}
