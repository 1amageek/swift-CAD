import CADCore

struct PlanePlaneSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Plane,
        second: CanonicalAnalyticSurface.Plane,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let cross = first.normal.cross(second.normal)
        if cross.length <= tolerance.angle {
            let residual = abs((second.origin - first.origin).dot(first.normal))
            guard residual > tolerance.distance else {
                return [.coincident(try SurfaceSurfaceCoincidence(
                    residual: residual,
                    tolerance: tolerance
                ))]
            }
            return []
        }

        let direction = try cross.normalized(tolerance: tolerance.angle)
        let denominator = cross.dot(cross)
        let firstConstant = first.normal.dot(first.origin - .origin)
        let secondConstant = second.normal.dot(second.origin - .origin)
        let originVector = (
            second.normal.cross(cross) * firstConstant
                + cross.cross(first.normal) * secondConstant
        ) / denominator
        return [try verifier.curve(
            .line(Line3D(origin: .origin + originVector, direction: direction)),
            kind: .transverse,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            sampleParameters: SurfaceSurfaceIntersectionVerifier.lineSamples,
            tolerance: tolerance
        )]
    }
}
