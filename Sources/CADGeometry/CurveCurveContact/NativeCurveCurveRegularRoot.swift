import CADCore

/// Original interval Krawczyk authority; projected coordinates only steer root isolation.
struct NativeCurveCurveRegularRoot {
    enum Result {
        case excluded
        case unresolved
        case unique(first: ScalarInterval, second: ScalarInterval, axes: (Int, Int))
    }

    func certificate(first: SurfaceIntervalVectorJet, second: SurfaceIntervalVectorJet,
        firstCenter: SurfaceIntervalVectorJet, secondCenter: SurfaceIntervalVectorJet,
        firstRange: ScalarInterval, secondRange: ScalarInterval,
        exactWitness: (Double, Double)? = nil) throws -> Result {
        func component(_ jet: SurfaceIntervalVectorJet, _ axis: Int) -> SurfaceIntervalJet {
            axis == 0 ? jet.x : axis == 1 ? jet.y : jet.z
        }
        func midpoint(_ interval: OutwardScalarInterval) -> Double {
            interval.lower + (interval.upper - interval.lower) * 0.5
        }
        var selected: (Int, Int)?
        var largest = 0.0
        for axes in [(0, 1), (0, 2), (1, 2)] {
            let a = midpoint(component(firstCenter, axes.0).derivativeU)
            let b = -midpoint(component(secondCenter, axes.0).derivativeU)
            let c = midpoint(component(firstCenter, axes.1).derivativeU)
            let d = -midpoint(component(secondCenter, axes.1).derivativeU)
            let determinant = a * d - b * c
            if determinant.isFinite, abs(determinant) > largest {
                largest = abs(determinant)
                selected = axes
            }
        }
        guard let axes = selected, largest > 0 else { return .unresolved }
        let a = midpoint(component(firstCenter, axes.0).derivativeU)
        let b = -midpoint(component(secondCenter, axes.0).derivativeU)
        let c = midpoint(component(firstCenter, axes.1).derivativeU)
        let d = -midpoint(component(secondCenter, axes.1).derivativeU)
        let determinant = a * d - b * c
        let inverse = [d / determinant, -b / determinant, -c / determinant, a / determinant]
        guard inverse.allSatisfy(\.isFinite) else { return .unresolved }
        let j00 = component(first, axes.0).derivativeU
        let j01 = -component(second, axes.0).derivativeU
        let j10 = component(first, axes.1).derivativeU
        let j11 = -component(second, axes.1).derivativeU
        let r00 = OutwardScalarInterval.exact(1) - .exact(inverse[0]) * j00 - .exact(inverse[1]) * j10
        let r01 = -.exact(inverse[0]) * j01 - .exact(inverse[1]) * j11
        let r10 = -.exact(inverse[2]) * j00 - .exact(inverse[3]) * j10
        let r11 = OutwardScalarInterval.exact(1) - .exact(inverse[2]) * j01 - .exact(inverse[3]) * j11
        let f0 = component(firstCenter, axes.0).value - component(secondCenter, axes.0).value
        let f1 = component(firstCenter, axes.1).value - component(secondCenter, axes.1).value
        let dx = OutwardScalarInterval(lower: firstRange.lower, upper: firstRange.upper) - .exact(firstRange.midpoint)
        let dy = OutwardScalarInterval(lower: secondRange.lower, upper: secondRange.upper) - .exact(secondRange.midpoint)
        let k0 = OutwardScalarInterval.exact(firstRange.midpoint) - .exact(inverse[0]) * f0
            - .exact(inverse[1]) * f1 + r00 * dx + r01 * dy
        let k1 = OutwardScalarInterval.exact(secondRange.midpoint) - .exact(inverse[2]) * f0
            - .exact(inverse[3]) * f1 + r10 * dx + r11 * dy
        guard k0.isFinite, k1.isFinite else { return .unresolved }
        if k0.upper < firstRange.lower || k0.lower > firstRange.upper
            || k1.upper < secondRange.lower || k1.lower > secondRange.upper { return .excluded }
        let firstWidth = OutwardScalarInterval.exact(firstRange.upper) - .exact(firstRange.lower)
        let secondWidth = OutwardScalarInterval.exact(secondRange.upper) - .exact(secondRange.lower)
        guard let secondToFirst = secondWidth.divided(by: firstWidth),
              let firstToSecond = firstWidth.divided(by: secondWidth) else { return .unresolved }
        let firstRow = OutwardScalarInterval.exact(r00.absoluteUpperBound)
            + .exact(r01.absoluteUpperBound) * secondToFirst
        let secondRow = OutwardScalarInterval.exact(r11.absoluteUpperBound)
            + .exact(r10.absoluteUpperBound) * firstToSecond
        if firstRow.upper < 1, secondRow.upper < 1, let witness = exactWitness {
            return .unique(first: try ScalarInterval(lower: witness.0, upper: witness.0),
                second: try ScalarInterval(lower: witness.1, upper: witness.1), axes: axes)
        }
        guard firstRow.upper < 1, secondRow.upper < 1,
              k0.lower > firstRange.lower, k0.upper < firstRange.upper,
              k1.lower > secondRange.lower, k1.upper < secondRange.upper else { return .unresolved }
        return .unique(first: try ScalarInterval(lower: k0.lower, upper: k0.upper),
            second: try ScalarInterval(lower: k1.lower, upper: k1.upper), axes: axes)
    }
}
