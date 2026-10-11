import CADCore

struct PlanePlaneSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Plane,
        second: CanonicalAnalyticSurface.Plane,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
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
            var usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: .legacy)
            let a = try OriginalSupportingPlaneEquation.prepared(source: firstSurface,
                tolerance: tolerance, remainingSourceDepth: usage.admission.remainingSourceDepth, usage: &usage)
            let b = try OriginalSupportingPlaneEquation.prepared(source: secondSurface,
                tolerance: tolerance, remainingSourceDepth: usage.admission.remainingSourceDepth, usage: &usage)
            if try a.normal.cross(b.normal, usage: &usage).isZero {
                let firstComponent = !a.normal.x.isZero ? a.normal.x : (!a.normal.y.isZero ? a.normal.y : a.normal.z)
                let secondComponent = !a.normal.x.isZero ? b.normal.x : (!a.normal.y.isZero ? b.normal.y : b.normal.z)
                let difference = try a.offset.multiplied(by: secondComponent, usage: &usage)
                    .subtracting(b.offset.multiplied(by: firstComponent, usage: &usage), usage: &usage)
                try CurrentTaskCancellationChecker().checkCancellation()
                return difference.isZero
                    ? [.coincident(try SurfaceSurfaceCoincidence(residual: 0, tolerance: tolerance))] : []
            }
        }

        // FIXME(INCOMPLETE_IMPLEMENTATION): The public SSI dispatcher still uses
        // numerical transverse plane publication. Complete original line/UV
        // authority and general procedural equation transport remain M7 work.
        let denominator = cross.dot(cross)
        guard denominator.isFinite, denominator > 0 else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original transverse planes have no representable numerical line coefficients.")
        }
        let direction = try cross.normalized(tolerance: min(tolerance.angle, cross.length * 0.5))
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
