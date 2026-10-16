/// Actual events from one preparation operation, independent of earlier queries.
public struct OriginalQueryPreparationDepth: Sendable {
    public let scalar: ExactScalarDepth
    public let sourceDepth: Int
    public let geometricDepth: Int
    public let transportDepth: Int
}
