public struct PortableSourceEncodingLimits: Sendable, Equatable {
    public let maximumBytes: Int
    public let maximumWork: Int
    public let maximumDepth: Int
    public init(maximumBytes: Int, maximumWork: Int, maximumDepth: Int) {
        self.maximumBytes = maximumBytes
        self.maximumWork = maximumWork
        self.maximumDepth = maximumDepth
    }
    public func validate() throws {
        guard maximumBytes > 0, maximumWork > 0, maximumDepth > 0 else {
            throw PortableSourceEncodingError.invalidLimits
        }
    }
}
