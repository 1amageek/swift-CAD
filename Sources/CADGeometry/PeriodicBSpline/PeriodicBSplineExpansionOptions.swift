import CADCore

/// Bounds the storage of a finite restriction of a cyclic curve.
public struct PeriodicBSplineExpansionOptions: Hashable, Sendable {
    public var maximumControlPointCount: Int

    public init(maximumControlPointCount: Int = 65_536) {
        self.maximumControlPointCount = maximumControlPointCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumControlPointCount > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A periodic expansion budget must allow a positive control count.")
        }
    }
}
