enum IncrementalReplayError: Error, Equatable {
    case stateMismatch(table: String)
}
