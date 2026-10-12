/// A successful import proves an exact value-preserving transfer into this domain.
public protocol ExactScalarImporting: Sendable {
    associatedtype Source: Sendable
    associatedtype Value: Sendable
    func importing<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing Source, using admission: inout A) throws(ExactScalarFailure) -> Value
}
