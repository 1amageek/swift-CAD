public struct BSplineKnotRemovalOptions: Sendable, Hashable {
    public let maximumGeneratedScalarCount: Int
    public let maximumWork: Int

    public init(maximumGeneratedScalarCount: Int = 1_048_576, maximumWork: Int = 16_777_216) {
        self.maximumGeneratedScalarCount = maximumGeneratedScalarCount
        self.maximumWork = maximumWork
    }
}
