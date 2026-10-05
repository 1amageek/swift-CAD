/// Failures specific to geometric screen projection.
public enum OrthographicProjectionError: Error, Equatable, Sendable {
    case invalidFrame
    case nonfiniteOutput
}
