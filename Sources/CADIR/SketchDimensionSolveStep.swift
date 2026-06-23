public struct SketchDimensionSolveStep: Codable, Sendable, Hashable {
    public var dimension: SketchDimension
    public var status: SketchDimensionSolveStatus
    public var reason: String?

    public init(
        dimension: SketchDimension,
        status: SketchDimensionSolveStatus,
        reason: String? = nil
    ) {
        self.dimension = dimension
        self.status = status
        self.reason = reason
    }
}
