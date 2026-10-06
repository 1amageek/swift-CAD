public enum BSplineKnotRemovalError: Error, Sendable, Equatable {
    case invalidInput(String)
    case toleranceRejected(certifiedUpperBound: Double, requested: Double)
    case numericalFailure(String)
    case resourceLimitExceeded
}
