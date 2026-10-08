/// One invocation owns all accumulated resources and observes cancellation.
public protocol ExactScalarAdmission: ~Copyable {
    mutating func checkpoint() throws(ExactScalarFailure)
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure)
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure)
    /// One retained root interval or accepted decomposition cell is about to be visited.
    /// Depth is already mapped to the caller axis; wrappers must forward every visit.
    /// The caller owns any cumulative cell ceiling independently of stored-cell limits.
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure)
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure)
}
