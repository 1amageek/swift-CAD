import Foundation
import CADCore

struct CoaxialConeConeSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Cone,
        second: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let axisResidual = first.axis.cross(second.axis).length
        guard axisResidual <= tolerance.angle else {
            throw unsupported(
                residual: axisResidual,
                tolerance: tolerance,
                message: "Cone-cone intersection requires parallel axes."
            )
        }
        let apexOffset = second.apex - first.apex
        let axialDistance = apexOffset.dot(first.axis)
        let radialOffset = apexOffset - first.axis * axialDistance
        guard radialOffset.length <= tolerance.distance else {
            throw unsupported(
                residual: radialOffset.length,
                tolerance: tolerance,
                message: "Cone-cone intersection requires a common axis."
            )
        }

        let angleResidual = abs(first.halfAngle - second.halfAngle)
        if apexOffset.length <= tolerance.distance,
           angleResidual <= tolerance.angle {
            return [.coincident(try SurfaceSurfaceCoincidence(
                residual: apexOffset.length,
                tolerance: tolerance
            ))]
        }
        if apexOffset.length == 0.0 {
            return [try verifier.point(
                first.apex,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )]
        }

        let firstSlope = 1.0 / tan(first.halfAngle)
        let secondSlope = 1.0 / tan(second.halfAngle)
        let denominatorTolerance = tolerance.angle * max(
            1.0,
            max(
                1.0 + firstSlope * firstSlope,
                1.0 + secondSlope * secondSlope
            )
        )
        var candidates: [(radius: Double, axis: Double)] = []
        for firstNappe in [-1.0, 1.0] {
            for secondNappe in [-1.0, 1.0] {
                let denominator = firstNappe * firstSlope
                    - secondNappe * secondSlope
                guard abs(denominator) > denominatorTolerance else {
                    continue
                }
                let radius = axialDistance / denominator
                guard radius >= -tolerance.distance else {
                    continue
                }
                appendCandidate(
                    radius: max(0.0, radius),
                    axis: firstNappe * radius * firstSlope,
                    to: &candidates,
                    tolerance: tolerance
                )
            }
        }

        var results: [SurfaceSurfaceIntersection] = []
        for candidate in candidates.sorted(by: candidateOrder) {
            let center = first.apex + first.axis * candidate.axis
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
                    normal: first.axis,
                    radius: candidate.radius
                )),
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            ))
        }
        return results
    }

    private func appendCandidate(
        radius: Double,
        axis: Double,
        to candidates: inout [(radius: Double, axis: Double)],
        tolerance: ModelingTolerance
    ) {
        guard !candidates.contains(where: {
            abs($0.radius - radius) <= tolerance.distance
                && abs($0.axis - axis) <= tolerance.distance
        }) else {
            return
        }
        candidates.append((radius: radius, axis: axis))
    }

    private func candidateOrder(
        _ lhs: (radius: Double, axis: Double),
        _ rhs: (radius: Double, axis: Double)
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
            code: .invalidInput,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
