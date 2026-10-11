/// Subtracts scoped structural identities from a complete source-bound graph product.
public protocol OriginalIssuedGraphSelfContactQuerying: Sendable {
    associatedtype Source: Sendable
    associatedtype FirstEvidence: Sendable
    associatedtype FirstCover: OriginalIssuedGraphSelfContactRequestReading where FirstCover.Source == Source
    associatedtype SecondEvidence: Sendable
    associatedtype SecondCover: OriginalIssuedGraphSelfContactRequestReading where SecondCover.Source == Source
    func contacts<A: ExactScalarAdmission & ~Copyable>(
        in raw: OriginalIssuedGraphRelations<Source,FirstEvidence,FirstCover,Source,SecondEvidence,SecondCover>,
        excluding identities: [OriginalParameterIdentity<Source,OriginalExactScalarDomain>],
        domainLimits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphSelfContacts<Source,FirstEvidence,FirstCover,SecondEvidence,SecondCover>
}
