import CADCore

public struct SnapQueryOptions: Sendable, Hashable {
    public var maximumDistance: Double?
    public var maximumCandidateCount: Int
    public var includesVertices: Bool
    public var includesEdges: Bool
    public var includesFaces: Bool

    public init(
        maximumDistance: Double? = nil,
        maximumCandidateCount: Int = 16,
        includesVertices: Bool = true,
        includesEdges: Bool = true,
        includesFaces: Bool = true
    ) {
        self.maximumDistance = maximumDistance
        self.maximumCandidateCount = maximumCandidateCount
        self.includesVertices = includesVertices
        self.includesEdges = includesEdges
        self.includesFaces = includesFaces
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        if let maximumDistance {
            guard maximumDistance.isFinite,
                  maximumDistance >= 0.0 else {
                throw GeometryError.invalidDistance(maximumDistance)
            }
        }
        guard maximumCandidateCount > 0 else {
            throw FeatureEvaluationError.invalidGraph("Snap query must request at least one candidate.")
        }
    }
}
