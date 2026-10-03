public struct ProductAttributeLimits: Sendable, Equatable {
    public let maximumRecords: Int
    public let maximumTargets: Int
    public let maximumDepth: Int
    public let maximumTextBytes: Int
    public let maximumWork: Int
    public init(maximumRecords: Int = 1_000_000, maximumTargets: Int = 1_000_000,
                maximumDepth: Int = 256, maximumTextBytes: Int = 256_000_000, maximumWork: Int = 100_000_000) {
        self.maximumRecords = maximumRecords; self.maximumTargets = maximumTargets; self.maximumDepth = maximumDepth
        self.maximumTextBytes = maximumTextBytes; self.maximumWork = maximumWork
    }
    public static let standard = Self()
    public func validate() throws {
        guard maximumRecords > 0, maximumTargets > 0, maximumDepth > 0, maximumTextBytes > 0, maximumWork > 0 else {
            throw ProductAttributeError.invalidSource("Product attribute limits must be positive.")
        }
    }
}
