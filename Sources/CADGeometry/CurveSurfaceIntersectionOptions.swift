import CADCore

public struct CurveSurfaceIntersectionOptions: Hashable, Sendable {
    public var curveRange: ScalarInterval?
    public var surfaceURange: ScalarInterval?
    public var surfaceVRange: ScalarInterval?
    public var maximumSubdivisionDepth: Int
    public var maximumSubdivisionCells: Int
    public var maximumIterations: Int
    public var maximumCandidateCount: Int
    public var maximumPolynomialDegree: Int

    public init(
        curveRange: ScalarInterval? = nil,
        surfaceURange: ScalarInterval? = nil,
        surfaceVRange: ScalarInterval? = nil,
        maximumSubdivisionDepth: Int = 8,
        maximumSubdivisionCells: Int = 262_144,
        maximumIterations: Int = 32,
        maximumCandidateCount: Int = 4_096,
        maximumPolynomialDegree: Int = 64
    ) {
        self.curveRange = curveRange
        self.surfaceURange = surfaceURange
        self.surfaceVRange = surfaceVRange
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumSubdivisionCells = maximumSubdivisionCells
        self.maximumIterations = maximumIterations
        self.maximumCandidateCount = maximumCandidateCount
        self.maximumPolynomialDegree = maximumPolynomialDegree
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 24,
              maximumSubdivisionCells > 0,
              maximumSubdivisionCells <= 4_194_304,
              maximumIterations > 0,
              maximumIterations <= 256,
              maximumCandidateCount > 0,
              maximumCandidateCount <= 65_536,
              maximumPolynomialDegree > 0,
              maximumPolynomialDegree <= 256 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Curve-surface intersection limits are outside the supported resource envelope."
            )
        }
    }
}
