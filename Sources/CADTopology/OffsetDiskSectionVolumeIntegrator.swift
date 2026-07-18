import Foundation
import CADCore

/// Integrates intersections of offset circular or annular cross-sections.
struct OffsetDiskSectionVolumeIntegrator {
    func volume(
        breakpoints: [Double],
        centerDistance: Double,
        characteristicLength: Double,
        tolerance: ModelingTolerance,
        firstRadiusAt: (Double) -> Double,
        secondRadiusAt: (Double) -> Double
    ) throws -> Double {
        try integratedVolume(
            breakpoints: breakpoints,
            centerDistance: centerDistance,
            characteristicLength: characteristicLength,
            tolerance: tolerance,
            integrand: { parameter in
                diskOverlapArea(
                    firstRadius: max(0.0, firstRadiusAt(parameter)),
                    secondRadius: max(0.0, secondRadiusAt(parameter)),
                    centerDistance: centerDistance
                )
            }
        )
    }

    func annulusIntersectionVolume(
        breakpoints: [Double],
        centerDistance: Double,
        characteristicLength: Double,
        tolerance: ModelingTolerance,
        firstInnerRadiusAt: (Double) -> Double,
        firstOuterRadiusAt: (Double) -> Double,
        secondInnerRadiusAt: (Double) -> Double,
        secondOuterRadiusAt: (Double) -> Double
    ) throws -> Double {
        try integratedVolume(
            breakpoints: breakpoints,
            centerDistance: centerDistance,
            characteristicLength: characteristicLength,
            tolerance: tolerance,
            integrand: { parameter in
                let firstInner = max(0.0, firstInnerRadiusAt(parameter))
                let firstOuter = max(firstInner, firstOuterRadiusAt(parameter))
                let secondInner = max(0.0, secondInnerRadiusAt(parameter))
                let secondOuter = max(secondInner, secondOuterRadiusAt(parameter))
                let area = diskOverlapArea(
                    firstRadius: firstOuter,
                    secondRadius: secondOuter,
                    centerDistance: centerDistance
                ) - diskOverlapArea(
                    firstRadius: firstInner,
                    secondRadius: secondOuter,
                    centerDistance: centerDistance
                ) - diskOverlapArea(
                    firstRadius: firstOuter,
                    secondRadius: secondInner,
                    centerDistance: centerDistance
                ) + diskOverlapArea(
                    firstRadius: firstInner,
                    secondRadius: secondInner,
                    centerDistance: centerDistance
                )
                return max(area, 0.0)
            }
        )
    }

    private func integratedVolume(
        breakpoints: [Double],
        centerDistance: Double,
        characteristicLength: Double,
        tolerance: ModelingTolerance,
        integrand: (Double) -> Double
    ) throws -> Double {
        try tolerance.validate()
        guard breakpoints.count >= 2,
              centerDistance > tolerance.distance,
              characteristicLength.isFinite,
              characteristicLength > tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Offset disk-section integration requires ordered spans and a positive offset."
            )
        }
        let targetError = max(
            tolerance.distance * characteristicLength * characteristicLength * 2.0,
            Double.ulpOfOne * pow(characteristicLength, 3.0) * 2_048.0
        )
        let spanCount = breakpoints.count - 1
        var result = 0.0
        for index in 0..<spanCount {
            let lower = breakpoints[index]
            let upper = breakpoints[index + 1]
            guard lower.isFinite,
                  upper.isFinite,
                  upper - lower > tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Offset disk-section integration received a degenerate span."
                )
            }
            result += try adaptiveIntegral(
                lower: lower,
                upper: upper,
                targetError: targetError / Double(spanCount),
                depth: 0,
                tolerance: tolerance,
                integrand: integrand
            )
        }
        return result
    }

    private func adaptiveIntegral(
        lower: Double,
        upper: Double,
        targetError: Double,
        depth: Int,
        tolerance: ModelingTolerance,
        integrand: (Double) -> Double
    ) throws -> Double {
        let midpoint = (lower + upper) * 0.5
        let coarse = gaussIntegral(lower: lower, upper: upper, integrand: integrand)
        let fine = gaussIntegral(lower: lower, upper: midpoint, integrand: integrand)
            + gaussIntegral(lower: midpoint, upper: upper, integrand: integrand)
        let error = abs(fine - coarse)
        if error <= targetError {
            return fine
        }
        guard depth < 20 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: error,
                tolerance: tolerance,
                message: "Offset disk-section volume exhausted its adaptive integration depth."
            )
        }
        return try adaptiveIntegral(
            lower: lower,
            upper: midpoint,
            targetError: targetError * 0.5,
            depth: depth + 1,
            tolerance: tolerance,
            integrand: integrand
        ) + adaptiveIntegral(
            lower: midpoint,
            upper: upper,
            targetError: targetError * 0.5,
            depth: depth + 1,
            tolerance: tolerance,
            integrand: integrand
        )
    }

    private func gaussIntegral(
        lower: Double,
        upper: Double,
        integrand: (Double) -> Double
    ) -> Double {
        let nodes = [
            -0.906_179_845_938_664,
            -0.538_469_310_105_683_1,
            0.0,
            0.538_469_310_105_683_1,
            0.906_179_845_938_664,
        ]
        let weights = [
            0.236_926_885_056_189_1,
            0.478_628_670_499_366_5,
            0.568_888_888_888_888_9,
            0.478_628_670_499_366_5,
            0.236_926_885_056_189_1,
        ]
        let midpoint = (lower + upper) * 0.5
        let halfSpan = (upper - lower) * 0.5
        var result = 0.0
        for index in nodes.indices {
            result += weights[index] * integrand(midpoint + halfSpan * nodes[index])
        }
        return result * halfSpan
    }

    private func diskOverlapArea(
        firstRadius: Double,
        secondRadius: Double,
        centerDistance: Double
    ) -> Double {
        guard firstRadius > 0.0,
              secondRadius > 0.0,
              centerDistance < firstRadius + secondRadius else {
            return 0.0
        }
        if centerDistance <= abs(firstRadius - secondRadius) {
            let containedRadius = min(firstRadius, secondRadius)
            return Double.pi * containedRadius * containedRadius
        }
        let distanceSquared = centerDistance * centerDistance
        let firstSquared = firstRadius * firstRadius
        let secondSquared = secondRadius * secondRadius
        let firstCosine = clampedUnit(
            (distanceSquared + firstSquared - secondSquared)
                / (2.0 * centerDistance * firstRadius)
        )
        let secondCosine = clampedUnit(
            (distanceSquared + secondSquared - firstSquared)
                / (2.0 * centerDistance * secondRadius)
        )
        let radicand = max(
            0.0,
            (-centerDistance + firstRadius + secondRadius)
                * (centerDistance + firstRadius - secondRadius)
                * (centerDistance - firstRadius + secondRadius)
                * (centerDistance + firstRadius + secondRadius)
        )
        return firstSquared * acos(firstCosine)
            + secondSquared * acos(secondCosine)
            - 0.5 * sqrt(radicand)
    }

    private func clampedUnit(_ value: Double) -> Double {
        min(max(value, -1.0), 1.0)
    }
}
