import CADCore

extension CertifiedAnalyticPairSurfaceParameterCurve {
    var hasFullBranchCylinderSpatialBounds: Bool {
        guard case let .cylinderCylinder(curve) = intersection.definition else {
            return false
        }
        return curve.componentKind == .negativeFullBranch
            || curve.componentKind == .positiveFullBranch
    }

    func fullBranchCylinderSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        guard case let .cylinderCylinder(curve) = intersection.definition,
              curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic-pair spatial bounds require a certified full-branch cylinder-cylinder component."
            )
        }
        let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
            tolerance: tolerance
        )
        let scale = abs(endFraction - startFraction).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: (source.first * scale).nextUp,
            second: ((source.second * scale).nextUp * scale).nextUp
        )
    }
}
