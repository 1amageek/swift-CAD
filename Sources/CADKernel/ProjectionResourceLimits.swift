import CADCore

public struct ProjectionResourceLimits: Codable, Sendable, Hashable {
    public var seedCount: Int
    public var maximumIterations: Int
    public var maximumSubdivisionDepth: Int
    public var maximumSubdivisionCells: Int
    public var maximumCandidateCount: Int

    private enum CodingKeys: String, CodingKey {
        case seedCount
        case maximumIterations
        case maximumSubdivisionDepth
        case maximumSubdivisionCells
        case maximumCandidateCount
    }

    public init(
        seedCount: Int = 64,
        maximumIterations: Int = 64,
        maximumSubdivisionDepth: Int = 32,
        maximumSubdivisionCells: Int = 1_048_576,
        maximumCandidateCount: Int = 4_096
    ) {
        self.seedCount = seedCount
        self.maximumIterations = maximumIterations
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumSubdivisionCells = maximumSubdivisionCells
        self.maximumCandidateCount = maximumCandidateCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .seedCount,
                .maximumIterations,
                .maximumSubdivisionDepth,
                .maximumSubdivisionCells,
                .maximumCandidateCount,
            ],
            in: decoder
        )
        seedCount = try container.decode(Int.self, forKey: .seedCount)
        maximumIterations = try container.decode(Int.self, forKey: .maximumIterations)
        maximumSubdivisionDepth = try container.decode(Int.self, forKey: .maximumSubdivisionDepth)
        maximumSubdivisionCells = try container.decode(Int.self, forKey: .maximumSubdivisionCells)
        maximumCandidateCount = try container.decode(Int.self, forKey: .maximumCandidateCount)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard seedCount >= 2,
              seedCount <= 65_536,
              maximumIterations > 0,
              maximumIterations <= 256,
              maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 32,
              maximumSubdivisionCells > 0,
              maximumSubdivisionCells <= 1_048_576,
              maximumCandidateCount > 0,
              maximumCandidateCount <= 65_536 else {
            throw KernelError(
                phase: .validation,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Projection resource limits are outside the supported envelope."
            )
        }
    }
}
