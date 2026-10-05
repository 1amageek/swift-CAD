import CADCore

/// Positive original tolerance correspondence with independently issued C0 authority.
struct OriginalContinuousCurveCurveToleranceCorrespondence {
    func proves(first: SurfaceIntervalVectorJet, second: SurfaceIntervalVectorJet,
        firstCenter: SurfaceIntervalVectorJet, secondCenter: SurfaceIntervalVectorJet,
        firstRange: ScalarInterval, secondRange: ScalarInterval, reversed: Bool,
        firstContinuity: PreparedCurveDifferentialEncloser.ContinuousFirstOrderSource,
        secondContinuity: PreparedCurveDifferentialEncloser.ContinuousFirstOrderSource,
        budget: inout NativeCurveCurveContactBudget) throws -> Bool {
        try budget.work(1)
        guard firstRange.width > 0, secondRange.width > 0,
            firstRange.lower >= firstContinuity.parameters.lower,
            firstRange.upper <= firstContinuity.parameters.upper,
            secondRange.lower >= secondContinuity.parameters.lower,
            secondRange.upper <= secondContinuity.parameters.upper else {
            throw GeometryConversionError.invalidInput("Original continuous correspondence exceeded its C0 source domain.")
        }
        let firstWidth = OutwardScalarInterval.exact(firstRange.upper) - .exact(firstRange.lower)
        let secondWidth = reversed
            ? OutwardScalarInterval.exact(secondRange.lower) - .exact(secondRange.upper)
            : OutwardScalarInterval.exact(secondRange.upper) - .exact(secondRange.lower)
        let firstError = (OutwardScalarInterval.exact(firstRange.lower) + .exact(firstRange.upper))
            * .exact(0.5) - .exact(firstRange.midpoint)
        let secondError = (OutwardScalarInterval.exact(secondRange.lower) + .exact(secondRange.upper))
            * .exact(0.5) - .exact(secondRange.midpoint)
        func square(_ a: SurfaceIntervalJet, _ b: SurfaceIntervalJet,
            _ ac: SurfaceIntervalJet, _ bc: SurfaceIntervalJet) throws -> OutwardScalarInterval {
            try budget.work(24)
            // C0 and the original piecewise D1 cover authorize integration.
            // No derivative continuity or D2 remainder is inferred at joins.
            let center = ac.value-bc.value
            let rounding = OutwardScalarInterval.exact(a.derivativeU.absoluteUpperBound)
                * .exact(firstError.absoluteUpperBound)
                + .exact(b.derivativeU.absoluteUpperBound) * .exact(secondError.absoluteUpperBound)
            let slope = a.derivativeU*firstWidth-b.derivativeU*secondWidth
            let bound = OutwardScalarInterval.exact(center.absoluteUpperBound) + rounding
                + .exact(0.5) * .exact(slope.absoluteUpperBound)
            guard bound.isFinite else { throw budget.exhausted() }
            return bound*bound
        }
        let residual = try square(first.x,second.x,firstCenter.x,secondCenter.x)
            + square(first.y,second.y,firstCenter.y,secondCenter.y)
            + square(first.z,second.z,firstCenter.z,secondCenter.z)
        let limit = OutwardScalarInterval.exact(budget.tolerance.distance) * .exact(budget.tolerance.distance)
        return residual.upper <= limit.lower
    }
}
