/// Immutable actual contributions of one lexical allocation scope.
public struct OriginalQueryAllocationScopeSnapshot: Sendable {
    public let work: Int
    public let storageBytes: Int
    public let records: Int
    public let sourceTextBytes: Int
    public let combinedUnits: Int?
}
