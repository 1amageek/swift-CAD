import CADCore

struct DefaultAnalyticSurfaceEquivalenceResolver:
    AnalyticSurfaceEquivalenceResolving
{
    func areEquivalent(
        _ first: Surface3D,
        _ second: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try tolerance.validate()
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        if first == second { return true }
        switch (
            CanonicalAnalyticSurface(first),
            CanonicalAnalyticSurface(second)
        ) {
        case let (.plane(first), .plane(second)):
            return AnalyticAxisRelation.areParallel(
                first.normal,
                second.normal,
                tolerance: tolerance
            ) && abs(
                (second.origin - first.origin).dot(first.normal)
            ) <= tolerance.distance
        case let (.sphere(first), .sphere(second)):
            return (first.center - second.center).length
                    <= tolerance.distance
                && abs(first.radius - second.radius)
                    <= tolerance.distance
        case let (.cylinder(first), .cylinder(second)):
            return AnalyticAxisRelation.areParallel(
                first.axis,
                second.axis,
                tolerance: tolerance
            ) && AnalyticAxisRelation.radialOffset(
                from: first.origin,
                axis: first.axis,
                to: second.origin
            ).length <= tolerance.distance
                && abs(first.radius - second.radius)
                    <= tolerance.distance
        case let (.cone(first), .cone(second)):
            return (first.apex - second.apex).length
                    <= tolerance.distance
                && AnalyticAxisRelation.areParallel(
                    first.axis,
                    second.axis,
                    tolerance: tolerance
                )
                && abs(first.halfAngle - second.halfAngle)
                    <= tolerance.angle
        case let (.torus(first), .torus(second)):
            return (first.center - second.center).length
                    <= tolerance.distance
                && AnalyticAxisRelation.areParallel(
                    first.axis,
                    second.axis,
                    tolerance: tolerance
                )
                && abs(first.majorRadius - second.majorRadius)
                    <= tolerance.distance
                && abs(first.minorRadius - second.minorRadius)
                    <= tolerance.distance
        default:
            return false
        }
    }
}
