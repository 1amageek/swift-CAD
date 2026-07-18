import CADCore

struct CoaxialTorusTorusSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Torus,
        second: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let axisResidual = first.axis.cross(second.axis).length
        guard axisResidual <= tolerance.angle else {
            throw unsupported(
                residual: axisResidual,
                tolerance: tolerance,
                message: "Torus-torus intersection requires parallel axes."
            )
        }
        let centerOffset = second.center - first.center
        let axialDistance = centerOffset.dot(first.axis)
        let radialOffset = centerOffset - first.axis * axialDistance
        guard radialOffset.length <= tolerance.distance else {
            throw unsupported(
                residual: radialOffset.length,
                tolerance: tolerance,
                message: "Torus-torus intersection requires a common axis."
            )
        }
        let meridian = try MeridianCircleIntersector().intersections(
            firstCenter: .init(radius: first.majorRadius, axis: 0.0),
            firstRadius: first.minorRadius,
            secondCenter: .init(
                radius: second.majorRadius,
                axis: axialDistance
            ),
            secondRadius: second.minorRadius,
            tolerance: tolerance
        )
        if meridian.isCoincident {
            let residual = max(
                axisResidual,
                max(
                    radialOffset.length,
                    max(
                        abs(first.majorRadius - second.majorRadius),
                        abs(first.minorRadius - second.minorRadius)
                    )
                )
            )
            return [.coincident(try SurfaceSurfaceCoincidence(
                residual: residual,
                tolerance: tolerance
            ))]
        }

        var results: [SurfaceSurfaceIntersection] = []
        for candidate in meridian.points {
            guard candidate.radius >= -tolerance.distance else {
                continue
            }
            let center = first.center + first.axis * candidate.axis
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
                kind: meridian.isTangent ? .tangent : .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            ))
        }
        return results
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
