/// Invocation-local cumulative accounting. Every derived collection is charged before growth.
public struct ProductAttributeBudget: Sendable {
    public let limits: ProductAttributeLimits
    public private(set) var consumedWork = 0
    public private(set) var consumedTargets = 0
    public private(set) var consumedTextBytes = 0
    public init(limits: ProductAttributeLimits) throws { try limits.validate(); self.limits = limits }
    public mutating func charge(work: Int = 0, targets: Int = 0, textBytes: Int = 0) throws {
        try Task.checkCancellation()
        guard work >= 0, targets >= 0, textBytes >= 0,
              work <= limits.maximumWork - consumedWork,
              targets <= limits.maximumTargets - consumedTargets,
              textBytes <= limits.maximumTextBytes - consumedTextBytes else {
            throw ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")
        }
        consumedWork += work; consumedTargets += targets; consumedTextBytes += textBytes
    }
}
