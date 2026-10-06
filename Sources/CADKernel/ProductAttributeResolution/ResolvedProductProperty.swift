import CADIR

public struct ResolvedProductProperty: Sendable, Equatable {
    public let value: ProductAttributeValue
    /// The first assignment is the base; the last is the effective override.
    public let assignmentChain: [ProductAttributeID]
    public init(value: ProductAttributeValue, assignmentChain: [ProductAttributeID]) {
        self.value = value; self.assignmentChain = assignmentChain
    }
}
