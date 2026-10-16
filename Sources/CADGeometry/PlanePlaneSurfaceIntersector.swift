import CADCore

struct PlanePlaneSurfaceIntersector {
    func intersections(
        first: CanonicalAnalyticSurface.Plane,
        second: CanonicalAnalyticSurface.Plane,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions = .init(),
        tolerance: ModelingTolerance, using usage: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection] {
        try usage.checkpoint()
        try usage.consumeWork(1)
        usage.context = usage.context.at(stage: .source)
        try first.requireLegacyUnitNormal(tolerance: tolerance)
        try second.requireLegacyUnitNormal(tolerance: tolerance)
        let cross = first.normal.cross(second.normal)
        func directlyAuthored(_ surface: Surface3D) -> Bool {
            switch surface {
            case .plane, .analytic(.plane): return true
            default: return false
            }
        }
        if cross.length <= tolerance.angle || (directlyAuthored(firstSurface) && directlyAuthored(secondSurface)) {
            let a = try OriginalSupportingPlaneEquation.prepared(source: firstSurface,
                tolerance: tolerance, remainingSourceDepth: usage.effectiveLimits.remainingSourceDepth, usage: &usage)
            let b = try OriginalSupportingPlaneEquation.prepared(source: secondSurface,
                tolerance: tolerance, remainingSourceDepth: usage.effectiveLimits.remainingSourceDepth, usage: &usage)
            if try a.normal.cross(b.normal, usage: &usage).isZero {
                let firstComponent = !a.normal.x.isZero ? a.normal.x : (!a.normal.y.isZero ? a.normal.y : a.normal.z)
                let secondComponent = !a.normal.x.isZero ? b.normal.x : (!a.normal.y.isZero ? b.normal.y : b.normal.z)
                let difference = try a.offset.multiplied(by: secondComponent, usage: &usage)
                    .subtracting(b.offset.multiplied(by: firstComponent, usage: &usage), usage: &usage)
                try usage.checkpoint()
                return difference.isZero
                    ? [.coincident(try SurfaceSurfaceCoincidence(residual: 0, tolerance: tolerance))] : []
            }
        }

        // FIXME(INCOMPLETE_IMPLEMENTATION): The public SSI dispatcher reaches
        // transverse planes here. Rounded line coefficients and sampled residuals
        // do not prove the original line or either UV correspondence. A retained
        // original line/UV receipt must be connected before this branch succeeds.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Original transverse plane publication requires a source-owned exact line and UV receipt.")
    }
}
