import CADCore

public struct CurveSurfaceIntersectionOptions: Hashable, Sendable {
    public var curveRange: ScalarInterval?
    public var surfaceURange: ScalarInterval?
    public var surfaceVRange: ScalarInterval?
    public var maximumSubdivisionDepth: Int
    public var maximumIterations: Int
    public var maximumSeedCount: Int

    public init(
        curveRange: ScalarInterval? = nil,
        surfaceURange: ScalarInterval? = nil,
        surfaceVRange: ScalarInterval? = nil,
        maximumSubdivisionDepth: Int = 8,
        maximumIterations: Int = 32,
        maximumSeedCount: Int = 1_024
    ) {
        self.curveRange = curveRange
        self.surfaceURange = surfaceURange
        self.surfaceVRange = surfaceVRange
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumIterations = maximumIterations
        self.maximumSeedCount = maximumSeedCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 24,
              maximumIterations > 0,
              maximumIterations <= 256,
              maximumSeedCount > 0,
              maximumSeedCount <= 65_536 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Curve-surface intersection limits are outside the supported resource envelope."
            )
        }
    }
}
