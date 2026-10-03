public enum GeometryConversionError: Error, Equatable, Sendable {
    case invalidInput(String)
    case resourceLimitExceeded(String)
    case toleranceRejected
}
