public enum PortableSourceEncodingError: Error, Equatable, Sendable {
    case invalidLimits
    case resourceLimitExceeded(String)
    case nonfiniteScalar
    case canonicalKeyCollision
}
