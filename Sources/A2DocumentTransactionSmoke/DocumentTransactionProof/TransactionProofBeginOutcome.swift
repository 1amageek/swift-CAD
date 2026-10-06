import SwiftCAD

enum TransactionProofBeginOutcome: Sendable {
    case accepted(DocumentTransactionToken)
    case rejected(DocumentTransactionError)
    case unexpected
}
