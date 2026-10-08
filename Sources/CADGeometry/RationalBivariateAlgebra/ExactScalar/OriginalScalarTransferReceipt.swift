/// Immutable source and destination authority for an ordered exact transfer.
public struct OriginalScalarTransferReceipt: Sendable {
    public let sources: [OriginalExactScalar]
    public let field: OriginalExactScalarDomain
    public let values: [OriginalExactScalar]

    init(sources: [OriginalExactScalar], field: OriginalExactScalarDomain,
        values: [OriginalExactScalar]) {
        self.sources = sources; self.field = field; self.values = values
    }
}
