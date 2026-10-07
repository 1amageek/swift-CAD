/// One invocation owns all accumulated resources and observes cancellation.
public protocol ExactScalarAdmission: ~Copyable {
    mutating func checkpoint() throws(ExactScalarFailure)
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure)
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure)
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure)
}
