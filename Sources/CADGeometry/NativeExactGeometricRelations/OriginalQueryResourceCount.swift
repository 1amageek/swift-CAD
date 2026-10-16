/// An observed count never substitutes a local counter for an opaque caller budget.
public enum OriginalQueryResourceCount: Sendable, Equatable {
    public enum UnknownReason: Sendable, Equatable { case notObserved, opaqueCallback }
    case known(Int)
    case unknown(UnknownReason)
    case unlimited
}
