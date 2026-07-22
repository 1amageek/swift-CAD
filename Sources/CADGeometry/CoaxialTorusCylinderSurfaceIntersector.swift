import Foundation
import CADCore

struct CoaxialTorusCylinderSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        torus: CanonicalAnalyticSurface.Torus,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let radialOffset = AnalyticAxisRelation.radialOffset(
            from: cylinder.origin,
            axis: cylinder.axis,
            to: torus.center
        )
        guard AnalyticAxisRelation.areParallel(torus.axis, cylinder.axis, tolerance: tolerance),
              radialOffset.length <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Coaxial torus-cylinder intersection requires coincident parallel axes."
            )
        }

        let radialDifference = cylinder.radius - torus.majorRadius
        let heightSquared = torus.minorRadius * torus.minorRadius
            - radialDifference * radialDifference
        let squaredTolerance = tolerance.distance * tolerance.distance
        guard heightSquared >= -squaredTolerance else { return [] }
        let height = sqrt(max(0.0, heightSquared))
        let tangentIntersection = height <= tolerance.distance
        var signs = [-1.0]
        if !tangentIntersection {
            signs.append(1.0)
        }
        return try signs.map { sign in
            try verifier.curve(
                .circle(Circle3D(
                    center: torus.center + torus.axis * (sign * height),
                    normal: torus.axis,
                    radius: cylinder.radius
                )),
                kind: tangentIntersection ? .tangent : .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )
        }
    }
}
