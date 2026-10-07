public struct ExactScalarLimits: Sendable {
    public let work: Int
    public let storageBytes: Int
    public let valueDepth: Int
    public let coefficientDepth: Int
    public init(work: Int, storageBytes: Int, valueDepth: Int, coefficientDepth: Int) throws(ExactScalarFailure) {
        guard work >= 0, storageBytes >= 0, valueDepth >= 0, coefficientDepth >= 0 else { throw .invalidSource }
        self.work = work; self.storageBytes = storageBytes
        self.valueDepth = valueDepth; self.coefficientDepth = coefficientDepth
    }
}
