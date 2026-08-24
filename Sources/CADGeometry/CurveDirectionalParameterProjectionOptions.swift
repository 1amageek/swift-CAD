import CADCore

public struct CurveDirectionalParameterProjectionOptions: Hashable, Sendable {
    public var parameterRange: ScalarInterval?
    public var range: DirectionalProjectionRange3D
    public var maximumSubdivisionDepth: Int
    public var maximumSubdivisionCells: Int
    public var maximumIterations: Int
    public var maximumCandidateCount: Int

    public init(
        parameterRange: ScalarInterval? = nil,
        range: DirectionalProjectionRange3D = .line,
        maximumSubdivisionDepth: Int = 24,
        maximumSubdivisionCells: Int = 1_048_576,
        maximumIterations: Int = 32,
        maximumCandidateCount: Int = 4_096
    ) {
        self.parameterRange = parameterRange
        self.range = range
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumSubdivisionCells = maximumSubdivisionCells
        self.maximumIterations = maximumIterations
        self.maximumCandidateCount = maximumCandidateCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try CurveSurfaceIntersectionOptions(
            curveRange: parameterRange,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumSubdivisionCells: maximumSubdivisionCells,
            maximumIterations: maximumIterations,
            maximumCandidateCount: maximumCandidateCount
        ).validate(tolerance: tolerance)
    }
}
