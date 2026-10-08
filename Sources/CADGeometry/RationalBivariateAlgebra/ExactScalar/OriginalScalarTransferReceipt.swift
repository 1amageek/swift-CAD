/// Immutable source and destination authority for an ordered exact transfer.
public struct OriginalScalarTransferReceipt: Sendable {
    public let sources: [OriginalExactScalar]
    public let field: OriginalExactScalarDomain
    public let values: [OriginalExactScalar]
    let transport: OriginalSingularFieldTransport
    let depth: ExactScalarDepth

    init(sources: [OriginalExactScalar], field: OriginalExactScalarDomain,
        values: [OriginalExactScalar], transport: OriginalSingularFieldTransport,
        depth: ExactScalarDepth) {
        self.sources = sources; self.field = field; self.values = values
        self.transport = transport; self.depth = depth
    }
}
