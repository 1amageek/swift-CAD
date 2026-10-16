/// Immutable snapshot of an actual query stage, request and already-retained authority.
public struct OriginalQueryFailureContext: Sendable {
    public enum Operation: Sendable, Equatable {
        case curveSurface, surfaceSurface, curveCurveContact, boundary, selfContact, projectedContact, embedding, conversion, unspecified
    }
    public enum Entry: Sendable, Equatable { case ordinary, admitted, prepared, membership, unspecified }
    public enum Stage: Sendable, Equatable { case request, source, domain, relation, refinement, publication, membership, unspecified }
    public let operation: Operation
    public let entry: Entry
    public let stage: Stage
    public let first: OriginalQueryFailureScope?
    public let second: OriginalQueryFailureScope?
    public let firstOwner: OriginalQueryRetainedOwner?
    public let secondOwner: OriginalQueryRetainedOwner?
    public let resource: OriginalQueryResourceObservation?
    public static var unspecified: Self { .init(operation: .unspecified, entry: .unspecified, stage: .unspecified) }
    public init(operation: Operation, entry: Entry, stage: Stage,
        first: OriginalQueryFailureScope? = nil, second: OriginalQueryFailureScope? = nil,
        firstOwner: OriginalQueryRetainedOwner? = nil, secondOwner: OriginalQueryRetainedOwner? = nil,
        resource: OriginalQueryResourceObservation? = nil) {
        self.operation = operation; self.entry = entry; self.stage = stage
        self.first = first; self.second = second
        self.firstOwner = firstOwner; self.secondOwner = secondOwner; self.resource = resource
    }
    public func at(stage: Stage) -> Self {
        .init(operation: operation, entry: entry, stage: stage, first: first, second: second,
            firstOwner: firstOwner, secondOwner: secondOwner, resource: resource)
    }
    public func retaining(first: OriginalQueryRetainedOwner? = nil, second: OriginalQueryRetainedOwner? = nil) -> Self {
        .init(operation: operation, entry: entry, stage: stage, first: self.first, second: self.second,
            firstOwner: first ?? firstOwner, secondOwner: second ?? secondOwner, resource: resource)
    }
    public func recording(resource: OriginalQueryResourceObservation) -> Self {
        .init(operation: operation, entry: entry, stage: stage, first: first, second: second,
            firstOwner: firstOwner, secondOwner: secondOwner, resource: resource)
    }
    @usableFromInline
    func fillingMissing(from outer: Self) -> Self {
        .init(operation: operation == .unspecified ? outer.operation : operation,
            entry: entry == .unspecified ? outer.entry : entry,
            stage: stage == .unspecified ? outer.stage : stage,
            first: first ?? outer.first, second: second ?? outer.second,
            firstOwner: firstOwner ?? outer.firstOwner, secondOwner: secondOwner ?? outer.secondOwner,
            resource: resource ?? outer.resource)
    }
}
