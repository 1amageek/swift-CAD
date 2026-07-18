import Foundation
import CADCore

struct CoaxialConeTorusSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        cone: CanonicalAnalyticSurface.Cone,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let axisResidual = cone.axis.cross(torus.axis).length
        guard axisResidual <= tolerance.angle else {
            throw unsupported(
                residual: axisResidual,
                tolerance: tolerance,
                message: "Cone-torus intersection requires parallel axes."
            )
        }
        let apexOffset = cone.apex - torus.center
        let apexAxis = apexOffset.dot(torus.axis)
        let apexRadial = apexOffset - torus.axis * apexAxis
        guard apexRadial.length <= tolerance.distance else {
            throw unsupported(
                residual: apexRadial.length,
                tolerance: tolerance,
                message: "Cone-torus intersection requires a common axis."
            )
        }

        let inverseTangent = 1.0 / tan(cone.halfAngle)
        let quadratic = 1.0 + inverseTangent * inverseTangent
        let constant = torus.majorRadius * torus.majorRadius
            + apexAxis * apexAxis
            - torus.minorRadius * torus.minorRadius
        var candidates: [(radius: Double, axis: Double, tangent: Bool)] = []
        for nappe in [-1.0, 1.0] {
            let linear = 2.0 * (
                apexAxis * nappe * inverseTangent
                    - torus.majorRadius
            )
            let discriminant = linear * linear
                - 4.0 * quadratic * constant
            let lengthScale = max(
                1.0,
                max(
                    abs(linear),
                    max(
                        abs(apexAxis),
                        torus.majorRadius + torus.minorRadius
                    )
                )
            )
            let discriminantTolerance = tolerance.distance * lengthScale
            guard discriminant >= -discriminantTolerance else {
                continue
            }
            let root = sqrt(max(0.0, discriminant))
            let radii = root <= tolerance.distance
                ? [-linear / (2.0 * quadratic)]
                : [
                    (-linear - root) / (2.0 * quadratic),
                    (-linear + root) / (2.0 * quadratic),
                ]
            for radius in radii where radius >= -tolerance.distance {
                let axis = apexAxis + nappe * radius * inverseTangent
                appendCandidate(
                    (max(0.0, radius), axis, root <= tolerance.distance),
                    to: &candidates,
                    tolerance: tolerance
                )
            }
        }

        var results: [SurfaceSurfaceIntersection] = []
        for candidate in candidates.sorted(by: candidateOrder) {
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
                kind: candidate.tangent ? .tangent : .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            ))
        }
        return results
    }

    private func appendCandidate(
        _ candidate: (radius: Double, axis: Double, tangent: Bool),
        to candidates: inout [(radius: Double, axis: Double, tangent: Bool)],
        tolerance: ModelingTolerance
    ) {
        if let index = candidates.firstIndex(where: {
            abs($0.radius - candidate.radius) <= tolerance.distance
                && abs($0.axis - candidate.axis) <= tolerance.distance
        }) {
            candidates[index].tangent = candidates[index].tangent
                && candidate.tangent
        } else {
            candidates.append(candidate)
        }
    }

    private func candidateOrder(
        _ lhs: (radius: Double, axis: Double, tangent: Bool),
        _ rhs: (radius: Double, axis: Double, tangent: Bool)
    ) -> Bool {
        if lhs.axis != rhs.axis { return lhs.axis < rhs.axis }
        return lhs.radius < rhs.radius
    }

    private func unsupported(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .unsupportedCapability,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
