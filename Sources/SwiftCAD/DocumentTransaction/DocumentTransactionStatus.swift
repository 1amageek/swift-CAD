public struct DocumentTransactionStatus: Sendable, Equatable {
    public let epoch: UInt64
    public let undoCount: Int
    public let redoCount: Int
    public let activeTransaction: DocumentTransactionToken?
    public let stagedCommandCount: Int
}
