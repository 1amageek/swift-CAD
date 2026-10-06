enum CorePortabilityProofFailure: Error, Sendable {
    case unexpectedValue(String)
    case expectedFailure(String)
    case missingCurrentTask
}
