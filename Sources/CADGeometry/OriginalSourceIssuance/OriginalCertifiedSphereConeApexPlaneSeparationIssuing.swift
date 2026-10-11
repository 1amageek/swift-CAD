/// Issues whole authored-support separation from the actual original plane.
public protocol OriginalCertifiedSphereConeApexPlaneSeparationIssuing: Sendable {
    func issue<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<OriginalCertifiedSphereConeApexSnapshot>,
        plane: borrowing OriginalPlaneBasisReceipt<OriginalPlaneSnapshot, OriginalPhysicalAngleScalarDomain>,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalCertifiedSphereConeApexPlaneSeparationReceipt
}
