import CADCore

/// Bounds control storage and homogeneous knot-insertion work for cyclic edits.
/// Tensor edits charge generated nets and conservative transient control-line storage.
public struct PeriodicBSplineExpansionOptions: Hashable, Sendable {
    public var maximumControlPointCount: Int
    public var maximumKnotInsertionWork: Int

    public init(maximumControlPointCount: Int = 65_536, maximumKnotInsertionWork: Int = 1_048_576) {
        self.maximumControlPointCount = maximumControlPointCount
        self.maximumKnotInsertionWork = maximumKnotInsertionWork
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumControlPointCount > 0, maximumKnotInsertionWork > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A periodic expansion budget must allow positive control and insertion-work counts.")
        }
    }
}
