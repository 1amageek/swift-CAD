import CADCore

/// Whole original closed jets bound a positive native parameter correspondence.
struct OriginalCurveCurveTaylorCorrespondence {
    func proves(first: SurfaceIntervalVectorJet, second: SurfaceIntervalVectorJet,
        firstCenter: SurfaceIntervalVectorJet, secondCenter: SurfaceIntervalVectorJet,
        firstRange: ScalarInterval, secondRange: ScalarInterval,
        reversed: Bool, budget: inout NativeCurveCurveContactBudget) throws -> Bool {
        try budget.work(192)
        let axes = [(first.x, second.x, firstCenter.x, secondCenter.x),
                    (first.y, second.y, firstCenter.y, secondCenter.y),
                    (first.z, second.z, firstCenter.z, secondCenter.z)]
        let firstWidth = OutwardScalarInterval.exact(firstRange.upper) - .exact(firstRange.lower)
        let secondWidth = reversed
            ? OutwardScalarInterval.exact(secondRange.lower) - .exact(secondRange.upper)
            : OutwardScalarInterval.exact(secondRange.upper) - .exact(secondRange.lower)
        let firstCenterError = (OutwardScalarInterval.exact(firstRange.lower) + .exact(firstRange.upper))
            * .exact(0.5) - .exact(firstRange.midpoint)
        let secondCenterError = (OutwardScalarInterval.exact(secondRange.lower) + .exact(secondRange.upper))
            * .exact(0.5) - .exact(secondRange.midpoint)
        var square = OutwardScalarInterval.exact(0)
        for (a, b, ac, bc) in axes {
            let midpointResidual = ac.value - bc.value
                + ac.derivativeU * firstCenterError - bc.derivativeU * secondCenterError
            let derivative = ac.derivativeU * firstWidth - bc.derivativeU * secondWidth
            let secondDerivative = a.secondDerivativeUU * firstWidth * firstWidth
                - b.secondDerivativeUU * secondWidth * secondWidth
            func correction(_ jet: SurfaceIntervalJet, _ error: OutwardScalarInterval,
                _ width: OutwardScalarInterval) -> OutwardScalarInterval {
                let e = OutwardScalarInterval.exact(error.absoluteUpperBound)
                let w = OutwardScalarInterval.exact(width.absoluteUpperBound)
                return .exact(0.5) * .exact(jet.secondDerivativeUU.absoluteUpperBound) * (e * e + e * w)
            }
            let bound = OutwardScalarInterval.exact(midpointResidual.absoluteUpperBound)
                + .exact(0.5) * .exact(derivative.absoluteUpperBound)
                + .exact(0.125) * .exact(secondDerivative.absoluteUpperBound)
                + correction(a, firstCenterError, firstWidth)
                + correction(b, secondCenterError, secondWidth)
            guard bound.isFinite else { throw budget.exhausted() }
            square = square + bound * bound
        }
        let limit = OutwardScalarInterval.exact(budget.tolerance.distance) * .exact(budget.tolerance.distance)
        return square.upper <= limit.lower
    }
}
