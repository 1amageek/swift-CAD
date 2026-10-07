public enum ExactScalarFailure: Error {
    case invalidSource, divisionByZero, incompatibleDomain
    case resourceLimit(ExactResource), cancelled, unresolved
    case unsupportedRepresentation, countOverflow, invalidEvidence
    case admissionRejected(any Error)
}
