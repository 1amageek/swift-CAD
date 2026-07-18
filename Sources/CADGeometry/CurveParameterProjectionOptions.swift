import CADCore

public struct CurveParameterProjectionOptions: Hashable, Sendable {
    public var parameterRange: ScalarInterval?
    public var maximumIterations: Int
    public var seedCount: Int

    public init(
        parameterRange: ScalarInterval? = nil,
        maximumIterations: Int = 32,
        seedCount: Int = 64
    ) {
        self.parameterRange = parameterRange
        self.maximumIterations = maximumIterations
        self.seedCount = seedCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumIterations > 0,
              maximumIterations <= 256,
              seedCount >= 2,
              seedCount <= 65_536 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Curve projection limits are outside the supported resource envelope."
            )
        }
        if let parameterRange {
            guard parameterRange.width > max(tolerance.angle, Double.ulpOfOne) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Curve projection parameter range is degenerate."
                )
            }
        }
    }
}
