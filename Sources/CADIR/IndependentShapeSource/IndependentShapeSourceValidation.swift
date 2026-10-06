/// Accounting from a completed source validation; it is not a geometry proof receipt.
public struct IndependentShapeSourceValidation: Equatable, Sendable {
    public let consumedRecords: Int
    public let consumedTextBytes: Int
    public let consumedWork: Int
    public let maximumObservedDepth: Int
    package init(consumedRecords: Int, consumedTextBytes: Int, consumedWork: Int, maximumObservedDepth: Int) {
        self.consumedRecords = consumedRecords; self.consumedTextBytes = consumedTextBytes
        self.consumedWork = consumedWork; self.maximumObservedDepth = maximumObservedDepth
    }
}
