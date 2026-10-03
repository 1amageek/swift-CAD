public enum STEPStringError: Error, Equatable, Sendable {
    case invalidLimits
    case malformed(String)
    case resourceLimitExceeded
}
