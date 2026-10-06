import CADCore

/// An opaque capability for one active draft in one session.
public struct DocumentTransactionToken: Sendable, Hashable {
    let sessionID: PortableIdentity128
    let transactionID: PortableIdentity128
    let baseEpoch: UInt64
}
