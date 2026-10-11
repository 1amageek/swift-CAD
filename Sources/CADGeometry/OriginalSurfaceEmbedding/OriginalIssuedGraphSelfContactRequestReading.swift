/// Retains the authored request authority when a complete family has no graph.
public protocol OriginalIssuedGraphSelfContactRequestReading: Sendable {
    associatedtype Source: Sendable
    var selfContactRequest: OriginalParameterSelection<Source,OriginalExactScalarDomain> { get }
}
