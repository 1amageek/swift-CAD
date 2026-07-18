import CADCore

public struct SurfaceSurfaceIntersectionOptions: Hashable, Sendable {
    public var maximumSubdivisionDepth: Int
    public var maximumIterations: Int
    public var maximumSeedCount: Int
    public var maximumPeriodicSeamAttempts: Int

    public init(
        maximumSubdivisionDepth: Int = 8,
        maximumIterations: Int = 32,
        maximumSeedCount: Int = 1_024,
        maximumPeriodicSeamAttempts: Int = 16
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumIterations = maximumIterations
        self.maximumSeedCount = maximumSeedCount
        self.maximumPeriodicSeamAttempts = maximumPeriodicSeamAttempts
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 24,
              maximumIterations > 0,
              maximumIterations <= 256,
              maximumSeedCount > 0,
              maximumSeedCount <= 65_536,
              maximumPeriodicSeamAttempts > 0,
              maximumPeriodicSeamAttempts <= 64 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Surface-surface intersection limits are outside the supported resource envelope."
            )
        }
    }
}
