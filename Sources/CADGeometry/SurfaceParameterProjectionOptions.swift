import CADCore

public struct SurfaceParameterProjectionOptions: Hashable, Sendable {
    public var maximumIterations: Int
    public var maximumSubdivisionDepth: Int
    public var maximumSubdivisionCells: Int
    public var maximumCandidateCount: Int

    public init(
        maximumIterations: Int = 64,
        maximumSubdivisionDepth: Int = 24,
        maximumSubdivisionCells: Int = 262_144,
        maximumCandidateCount: Int = 4_096
    ) {
        self.maximumIterations = maximumIterations
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumSubdivisionCells = maximumSubdivisionCells
        self.maximumCandidateCount = maximumCandidateCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumIterations > 0,
              maximumIterations <= 256,
              maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 32,
              maximumSubdivisionCells > 0,
              maximumSubdivisionCells <= 4_194_304,
              maximumCandidateCount > 0,
              maximumCandidateCount <= 65_536 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Surface projection limits are outside the supported resource envelope."
            )
        }
    }
}
