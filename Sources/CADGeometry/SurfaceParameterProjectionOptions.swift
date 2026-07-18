import CADCore

public struct SurfaceParameterProjectionOptions: Hashable, Sendable {
    public var maximumIterations: Int
    public var seedCountPerDirection: Int
    public var refinementSeedCount: Int

    public init(
        maximumIterations: Int = 48,
        seedCountPerDirection: Int = 12,
        refinementSeedCount: Int = 8
    ) {
        self.maximumIterations = maximumIterations
        self.seedCountPerDirection = seedCountPerDirection
        self.refinementSeedCount = refinementSeedCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumIterations > 0,
              maximumIterations <= 256,
              seedCountPerDirection >= 2,
              seedCountPerDirection <= 256,
              refinementSeedCount > 0,
              refinementSeedCount <= 64 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Surface projection limits are outside the supported resource envelope."
            )
        }
    }
}
