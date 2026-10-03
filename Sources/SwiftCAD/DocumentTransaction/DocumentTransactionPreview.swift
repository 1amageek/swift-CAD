import CADIR

/// Validated source data for a draft; this is not an evaluated geometry result.
public struct DocumentTransactionPreview: Sendable {
    public let sourceDocument: CADDocument
    public let baseEpoch: UInt64
    public let commandCount: Int
}
