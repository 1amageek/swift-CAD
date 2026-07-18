import Foundation
import CADCore

struct ParallelCylinderSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Cylinder,
        second: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        guard AnalyticAxisRelation.areParallel(first.axis, second.axis, tolerance: tolerance) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Parallel-cylinder evaluation requires parallel axes."
            )
        }

        let radialOffset = AnalyticAxisRelation.radialOffset(
            from: first.origin,
            axis: first.axis,
            to: second.origin
        )
        let axisDistance = radialOffset.length
        if axisDistance <= tolerance.distance {
            let radiusResidual = abs(first.radius - second.radius)
            guard radiusResidual <= tolerance.distance else { return [] }
            return [.coincident(try SurfaceSurfaceCoincidence(
                residual: max(axisDistance, radiusResidual),
                tolerance: tolerance
            ))]
        }

        guard axisDistance <= first.radius + second.radius + tolerance.distance,
              axisDistance + min(first.radius, second.radius)
                >= max(first.radius, second.radius) - tolerance.distance else {
            return []
        }
        let radialDirection = try radialOffset.normalized(tolerance: tolerance.distance)
        let baseDistance = (
            first.radius * first.radius
                - second.radius * second.radius
                + axisDistance * axisDistance
        ) / (2.0 * axisDistance)
        let transverseSquared = max(
            0.0,
            first.radius * first.radius - baseDistance * baseDistance
        )
        let transverseDistance = sqrt(transverseSquared)
        let basePoint = first.origin + radialDirection * baseDistance
        let perpendicular = try first.axis.cross(radialDirection).normalized(
            tolerance: tolerance.angle
        )
        let kind: CurveSurfaceIntersectionKind = transverseDistance <= tolerance.distance
            ? .tangent
            : .transverse
        var results = [try line(
            origin: basePoint + perpendicular * transverseDistance,
            direction: first.axis,
            kind: kind,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )]
        if kind == .transverse {
            results.append(try line(
                origin: basePoint + perpendicular * -transverseDistance,
                direction: first.axis,
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            ))
        }
        return results
    }

    private func line(
        origin: Point3D,
        direction: Vector3D,
        kind: CurveSurfaceIntersectionKind,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        try verifier.curve(
            .line(Line3D(origin: origin, direction: direction)),
            kind: kind,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            sampleParameters: SurfaceSurfaceIntersectionVerifier.lineSamples,
            tolerance: tolerance
        )
    }
}
