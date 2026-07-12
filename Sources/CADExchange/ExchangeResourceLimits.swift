import CADCore

public struct ExchangeResourceLimits: Codable, Equatable, Sendable {
    public var maximumBytes: Int
    public var maximumEntities: Int
    public var maximumNesting: Int
    public var maximumIterations: Int

    public init(
        maximumBytes: Int = 64 * 1024 * 1024,
        maximumEntities: Int = 1_000_000,
        maximumNesting: Int = 256,
        maximumIterations: Int = 10_000_000
    ) {
        self.maximumBytes = maximumBytes
        self.maximumEntities = maximumEntities
        self.maximumNesting = maximumNesting
        self.maximumIterations = maximumIterations
    }

    public static let standard = ExchangeResourceLimits()

    public func validate() throws {
        guard maximumBytes > 0,
              maximumEntities > 0,
              maximumNesting > 0,
              maximumIterations > 0 else {
            throw KernelError(
                phase: .exchange,
                code: .invalidInput,
                message: "Exchange resource limits must be positive."
            )
        }
    }
}
