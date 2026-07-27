import CADCore

public struct CurveParameterProjectionOptions: Hashable, Sendable {
    static let maximumSupportedSubdivisionCells = 1_048_576

    public var parameterRange: ScalarInterval?
    public var maximumIterations: Int
    public var seedCount: Int
    public var maximumSubdivisionDepth: Int
    public var maximumSubdivisionCells: Int
    public var maximumCandidateCount: Int

    public init(
        parameterRange: ScalarInterval? = nil,
        maximumIterations: Int = 32,
        seedCount: Int = 64,
        maximumSubdivisionDepth: Int = 24,
        maximumSubdivisionCells: Int = 131_072,
        maximumCandidateCount: Int = 4_096
    ) {
        self.parameterRange = parameterRange
        self.maximumIterations = maximumIterations
        self.seedCount = seedCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumSubdivisionCells = maximumSubdivisionCells
        self.maximumCandidateCount = maximumCandidateCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumIterations > 0,
              maximumIterations <= 256,
              seedCount >= 2,
              seedCount <= 65_536,
              maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 32,
              maximumSubdivisionCells > 0,
              maximumSubdivisionCells <= Self.maximumSupportedSubdivisionCells,
              maximumCandidateCount > 0,
              maximumCandidateCount <= 65_536 else {
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
