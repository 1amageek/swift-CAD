/// Exclusive contributions observed by the currently active conversion scope.
public struct OriginalQueryConversionScopeSnapshot: Sendable {
    public let work: Int
    public let scalarSlots: Int
    public let certificationBoxes: Int
}
