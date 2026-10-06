import CADCore

extension BSplineSurface3D {
    func representativeProjection(
        _ projection: SurfaceParameterProjection, target: Point3D,
        requiringInverseTolerance: Bool, tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        guard isUPeriodic || isVPeriodic else { return projection }
        if requiringInverseTolerance {
            // Inverse parameters require a regular chart. The existing normal
            // contract owns rank/metric conditioning; a collapsed cycle is not a unique root.
            _ = try normal(u: projection.u, v: projection.v, tolerance: tolerance)
        }
        let u = isUPeriodic ? try normalizedParameter(projection.u, direction: .u, tolerance: tolerance) : projection.u
        let v = isVPeriodic ? try normalizedParameter(projection.v, direction: .v, tolerance: tolerance) : projection.v
        let actual = try point(u: u, v: v, tolerance: tolerance)
        let residual = (actual - target).length.nextUp
        let allowed = requiringInverseTolerance ? tolerance.distance : projection.residual.nextUp
        guard residual <= allowed else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                residual: residual, tolerance: tolerance,
                message: "Finite periodic representatives could not retain the certified projection residual.")
        }
        return try SurfaceParameterProjection(u: u, v: v, point: actual,
            residual: residual, iterations: projection.iterations)
    }

    /// Maps a closed box axis to conservative base-chart intervals without copying controls.
    func enclosureIntervals(
        _ interval: ScalarInterval, direction: SurfaceParameterDirection,
        tolerance: ModelingTolerance
    ) throws -> [ScalarInterval] {
        let periodic = direction == .u ? isUPeriodic : isVPeriodic
        guard periodic else { return [interval] }
        let knots = direction == .u ? uKnots : vKnots
        let degree = direction == .u ? uDegree : vDegree
        let count = direction == .u ? uControlPointCount : vControlPointCount
        try BSplineCurve3D.validatePeriodicDerivativeCertificate(degree: degree,
            knots: knots, controlPointCount: count, over: interval, tolerance: tolerance)
        let lower = knots[degree], upper = knots[count], period = upper - lower
        let wholeCycle = try ScalarInterval(lower: lower, upper: upper)
        // Account for finite remainder and translated-endpoint resolution. Complete
        // cycle coverage is deliberate conservative enclosure, never a geometry fallback.
        let margin = max(1, abs(interval.lower), abs(interval.upper), abs(lower), abs(upper)) * Double.ulpOfOne * 16
        let width = (interval.width.nextUp + 2 * margin).nextUp
        guard width < period else { return [wholeCycle] }
        let representative = try BSplineCurve3D.representative(interval.lower,
            origin: lower, period: period, tolerance: tolerance)
        let start = try BSplineCurve3D.representative(representative - margin,
            origin: lower, period: period, tolerance: tolerance)
        let end = (start + width).nextUp
        if end < upper {
            return [try ScalarInterval(lower: max(lower, start.nextDown), upper: end)]
        }
        return [
            try ScalarInterval(lower: max(lower, start.nextDown), upper: upper),
            try ScalarInterval(lower: lower, upper: min(upper, (lower + (end - upper).nextUp).nextUp)),
        ]
    }
}
