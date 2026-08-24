import CADCore

/// Reuses the exact Bezier decomposition of one immutable B-spline surface
/// while independently restricting interval jets to each requested box.
package struct PreparedBSplineSurfaceDifferentialEncloser: Sendable {
    package let surface: BSplineSurface3D
    private let patches: [RationalBezierSurfacePatch3D]

    package init(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        try surface.validate(tolerance: tolerance)
        self.surface = surface
        patches = try BSplineSurfaceBezierDecomposer().surfacePatches(
            surface: surface,
            tolerance: tolerance
        )
    }

    func intervalJet(
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        try parameters.validate(
            for: .bSpline(surface),
            tolerance: tolerance
        )
        let encloser = RationalBezierSurfaceJetEncloser()
        var result: SurfaceIntervalVectorJet?
        for patch in patches {
            let uLower = max(parameters.u.lower, patch.uLower)
            let uUpper = min(parameters.u.upper, patch.uUpper)
            let vLower = max(parameters.v.lower, patch.vLower)
            let vUpper = min(parameters.v.upper, patch.vUpper)
            guard uUpper > uLower, vUpper > vLower else { continue }
            let stableU = try numericallyStableInterval(
                ScalarInterval(lower: uLower, upper: uUpper),
                within: (lower: patch.uLower, upper: patch.uUpper),
                tolerance: tolerance
            )
            let stableV = try numericallyStableInterval(
                ScalarInterval(lower: vLower, upper: vUpper),
                within: (lower: patch.vLower, upper: patch.vUpper),
                tolerance: tolerance
            )
            let patchJet = try encloser.enclosure(
                of: patch,
                u: stableU,
                v: stableV,
                tolerance: tolerance
            )
            result = result.map { $0.union(patchJet) } ?? patchJet
        }
        guard let result else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The surface parameter box did not intersect a prepared B-spline Bezier span."
            )
        }
        return result
    }

    private func numericallyStableInterval(
        _ interval: ScalarInterval,
        within bounds: (lower: Double, upper: Double),
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        let scale = max(1.0, abs(bounds.lower), abs(bounds.upper))
        let requestedWidth = max(
            tolerance.relative * scale * 4.0,
            Double.ulpOfOne * scale * 4_096.0
        )
        let minimumWidth = min(requestedWidth, bounds.upper - bounds.lower)
        guard interval.width < minimumWidth else { return interval }

        // Expand from the certified endpoints instead of reconstructing them
        // from the midpoint. The latter can round inward and lose containment
        // for intervals close to a Bezier-span boundary.
        let lower = max(bounds.lower, interval.lower - minimumWidth)
        let upper = min(bounds.upper, interval.upper + minimumWidth)
        guard lower <= interval.lower,
              upper >= interval.upper,
              upper > lower else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: upper - lower,
                tolerance: tolerance,
                message: "A prepared B-spline differential enclosure could not construct a stable containing interval."
            )
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }
}
