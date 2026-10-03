public enum DocumentTransactionError: Error, Sendable, Equatable {
    case invalidLimits
    case staleEpoch(expected: UInt64, actual: UInt64)
    case foreignToken
    case staleTransaction
    case transactionAlreadyActive
    case activeTransaction
    case emptyCommandBatch
    case emptyTransaction
    case resourceLimitExceeded(String)
    case noUndo
    case noRedo
    case incompatibleEditorOutput
    case incompatibleEvaluationOutput
}
