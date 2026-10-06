/// Explicit bounds for retained history and staged command work.
public struct DocumentTransactionLimits: Sendable, Equatable {
    public let maximumHistoryEntries: Int
    public let maximumCommandsPerTransaction: Int

    public init(maximumHistoryEntries: Int, maximumCommandsPerTransaction: Int) throws {
        guard maximumHistoryEntries > 0, maximumCommandsPerTransaction > 0 else {
            throw DocumentTransactionError.invalidLimits
        }
        self.maximumHistoryEntries = maximumHistoryEntries
        self.maximumCommandsPerTransaction = maximumCommandsPerTransaction
    }
}
