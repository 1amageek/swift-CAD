import Foundation

/// An opaque capability for one active draft in one session.
public struct DocumentTransactionToken: Sendable, Hashable {
    let sessionID: UUID
    let transactionID: UUID
    let baseEpoch: UInt64
}
