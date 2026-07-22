import Foundation
import CADCore

struct CoaxialSphereConeSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        sphere: CanonicalAnalyticSurface.Sphere,
        cone: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let centerOffset = sphere.center - cone.apex
        let axialCenter = centerOffset.dot(cone.axis)
        let radialCenter = centerOffset - cone.axis * axialCenter
        guard radialCenter.length <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The coaxial sphere-cone intersector requires the sphere center to lie on the cone axis."
            )
        }

        let tangent = tan(cone.halfAngle)
        let quadraticA = 1.0 + tangent * tangent
        let quadraticB = -2.0 * axialCenter
        let quadraticC = axialCenter * axialCenter - sphere.radius * sphere.radius
        let discriminant = quadraticB * quadraticB - 4.0 * quadraticA * quadraticC
        let discriminantTolerance = tolerance.distance * tolerance.distance
        guard discriminant >= -discriminantTolerance else { return [] }
        let tangentIntersection = abs(discriminant) <= discriminantTolerance
        let root = sqrt(max(0.0, discriminant))
        var axialParameters = [(-quadraticB - root) / (2.0 * quadraticA)]
        if !tangentIntersection {
            axialParameters.append((-quadraticB + root) / (2.0 * quadraticA))
        }

        return try axialParameters.map { axialParameter in
            let center = cone.apex + cone.axis * axialParameter
            let radius = abs(axialParameter) * tangent
            if radius <= tolerance.distance {
                return try verifier.point(
                    center,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                )
            }
            return try verifier.curve(
                .circle(Circle3D(center: center, normal: cone.axis, radius: radius)),
                kind: tangentIntersection ? .tangent : .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )
        }
    }
}
