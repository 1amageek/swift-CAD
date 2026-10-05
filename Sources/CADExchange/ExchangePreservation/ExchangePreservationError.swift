public enum ExchangePreservationError: Error, Equatable, Sendable {
    case unacceptedLoss(ExchangePreservationReport)
    case invalidReference(entity: Int, missing: Int)
    case emptyRetainedSource
    case unsupportedPolicyFormat
}
