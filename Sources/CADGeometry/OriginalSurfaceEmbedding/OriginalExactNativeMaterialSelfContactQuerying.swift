/// Consumes retained self-contact and exact face material authority for both tuples.
public protocol OriginalExactNativeMaterialSelfContactQuerying: Sendable {
    func contacts<A: ExactScalarAdmission & ~Copyable>(
        in residual: OriginalExactNativeSelfContacts,
        first: OriginalExactNativeBoundaryDomain, second: OriginalExactNativeBoundaryDomain,
        selection: OriginalNativeBoundaryDomain.Selection,
        domainLimits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactNativeMaterialSelfContacts
}
