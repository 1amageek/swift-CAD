import Foundation
import CADCore

struct SurfaceParameterRangeResolver {
    func resolvedParameter(
        _ value: Double,
        domain: ParameterDomain,
        requestedRange: ScalarInterval?,
        tolerance: ModelingTolerance
    ) -> Double? {
        guard value.isFinite else { return nil }
        guard let requestedRange else { return value }
        let boundaryTolerance = parameterTolerance(
            for: domain,
            tolerance: tolerance
        )
        switch domain {
        case let .periodic(period):
            let lowerIndex = ceil(
                (requestedRange.lower - boundaryTolerance - value) / period
            )
            let upperIndex = floor(
                (requestedRange.upper + boundaryTolerance - value) / period
            )
            guard lowerIndex.isFinite,
                  upperIndex.isFinite,
                  lowerIndex <= upperIndex else {
                return nil
            }
            let preferredIndex = (
                (requestedRange.midpoint - value) / period
            ).rounded()
            let selectedIndex = min(
                max(preferredIndex, lowerIndex),
                upperIndex
            )
            let resolved = value + selectedIndex * period
            return resolved.isFinite ? resolved : nil
        case .closed, .unbounded:
            return contains(
                value,
                range: requestedRange,
                tolerance: boundaryTolerance
            ) ? value : nil
        }
    }

    private func parameterTolerance(
        for domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) -> Double {
        let machineFloor = Double.ulpOfOne * 128.0
        switch domain {
        case .unbounded:
            return max(tolerance.distance, machineFloor)
        case let .closed(lower, upper):
            let scale = max(abs(lower), max(abs(upper), upper - lower))
            return max(
                tolerance.angle,
                max(tolerance.relative * max(scale, 1.0), machineFloor)
            )
        case let .periodic(period):
            return max(
                tolerance.angle,
                max(tolerance.relative * period, machineFloor)
            )
        }
    }

    private func contains(
        _ value: Double,
        range: ScalarInterval,
        tolerance: Double
    ) -> Bool {
        value >= range.lower - tolerance
            && value <= range.upper + tolerance
    }
}
