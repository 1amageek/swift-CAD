public struct DocumentEvaluationMetrics: Codable, Sendable, Hashable {
    public var totalFeatureCount: Int
    public var rebuiltFeatureCount: Int
    public var reusedFeatureCount: Int
    public var invalidatedFeatureCount: Int
    public var replayFallbackCount: Int
    public var tessellatedBodyCount: Int
    public var reusedMeshCount: Int
    public var scopedBodyReadCount: Int
    public var maximumScopedBodyReadCount: Int
    public var topologyMutationCount: Int

    public init(
        totalFeatureCount: Int = 0,
        rebuiltFeatureCount: Int = 0,
        reusedFeatureCount: Int = 0,
        invalidatedFeatureCount: Int = 0,
        replayFallbackCount: Int = 0,
        tessellatedBodyCount: Int = 0,
        reusedMeshCount: Int = 0,
        scopedBodyReadCount: Int = 0,
        maximumScopedBodyReadCount: Int = 0,
        topologyMutationCount: Int = 0
    ) {
        self.totalFeatureCount = totalFeatureCount
        self.rebuiltFeatureCount = rebuiltFeatureCount
        self.reusedFeatureCount = reusedFeatureCount
        self.invalidatedFeatureCount = invalidatedFeatureCount
        self.replayFallbackCount = replayFallbackCount
        self.tessellatedBodyCount = tessellatedBodyCount
        self.reusedMeshCount = reusedMeshCount
        self.scopedBodyReadCount = scopedBodyReadCount
        self.maximumScopedBodyReadCount = maximumScopedBodyReadCount
        self.topologyMutationCount = topologyMutationCount
    }
}
