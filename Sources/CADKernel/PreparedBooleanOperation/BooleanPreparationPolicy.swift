import CADCore

/// Explicit geometric policy shared by preparation and every derived evaluation.
public struct BooleanPreparationPolicy: Sendable, Hashable {
    public let additionalDistanceTolerance: Double

    public init(additionalDistanceTolerance: Double = 0) {
        self.additionalDistanceTolerance = additionalDistanceTolerance
    }

    public func effectiveTolerance(from tolerance: ModelingTolerance) throws -> ModelingTolerance {
        try tolerance.validate()
        guard additionalDistanceTolerance.isFinite, additionalDistanceTolerance >= 0,
              (tolerance.distance + additionalDistanceTolerance).isFinite else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Boolean additional distance tolerance must be finite and nonnegative.")
        }
        var effective = tolerance
        effective.distance += additionalDistanceTolerance
        try effective.validate()
        return effective
    }
}
