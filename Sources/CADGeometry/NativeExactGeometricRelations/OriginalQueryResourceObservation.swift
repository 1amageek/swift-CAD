/// Immutable observations from the owner that rejected an actual resource request.
public struct OriginalQueryResourceObservation: Sendable, Equatable {
    public let axis: OriginalQueryResourceAxis
    public let used: OriginalQueryResourceCount
    public let limit: OriginalQueryResourceCount
    public let requested: OriginalQueryResourceCount
    public init(axis: OriginalQueryResourceAxis,
        used: OriginalQueryResourceCount = .unknown(.notObserved),
        limit: OriginalQueryResourceCount = .unknown(.notObserved),
        requested: OriginalQueryResourceCount = .unknown(.notObserved)) {
        self.axis = axis; self.used = used; self.limit = limit; self.requested = requested
    }
}
