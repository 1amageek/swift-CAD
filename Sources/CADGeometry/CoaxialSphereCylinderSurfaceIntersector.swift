import Foundation
import CADCore

struct CoaxialSphereCylinderSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        sphere: CanonicalAnalyticSurface.Sphere,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let radialOffset = AnalyticAxisRelation.radialOffset(
            from: cylinder.origin,
            axis: cylinder.axis,
            to: sphere.center
        )
        guard radialOffset.length <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Non-coaxial sphere-cylinder quartic intersections are not implemented."
            )
        }
        guard cylinder.radius <= sphere.radius + tolerance.distance else { return [] }
        let heightSquared = max(
            0.0,
            sphere.radius * sphere.radius - cylinder.radius * cylinder.radius
        )
        let height = sqrt(heightSquared)
        if height <= tolerance.distance {
            return [try circle(
                center: sphere.center,
                normal: cylinder.axis,
                radius: cylinder.radius,
                kind: .tangent,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )]
        }
        return try [-1.0, 1.0].map { sign in
            try circle(
                center: sphere.center + cylinder.axis * (sign * height),
                normal: cylinder.axis,
                radius: cylinder.radius,
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
    }

    private func circle(
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        kind: CurveSurfaceIntersectionKind,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        try verifier.curve(
            .circle(Circle3D(center: center, normal: normal, radius: radius)),
            kind: kind,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
            tolerance: tolerance
        )
    }
}
