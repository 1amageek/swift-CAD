#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalRationalParameterIdentityIssuing: OriginalParameterIdentityIssuing where Field: ExactScalarImporting {
    func collapsed<Selection: Sendable,A: ExactScalarAdmission & ~Copyable>(law: borrowing OriginalRationalChartReceipt<Source,Selection,Field>,
        on scope: borrowing OriginalParameterSelection<Source,Field>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
    func declaredBoundary<A: ExactScalarAdmission & ~Copyable>(declaration: OriginalSourceBoundaryDeclaration<Source>,
        left: borrowing OriginalRationalChartReceipt<Source,OriginalBSplineChartSelection,Field>,right: borrowing OriginalRationalChartReceipt<Source,OriginalBSplineChartSelection,Field>,
        scope: borrowing OriginalParameterSelection<Source,Field>,rightFrame: borrowing OriginalParameterFrame<Source,Field>,permutation: [Int],gains: [Field.Value],offsets: [Field.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
    func chartBoundary<A: ExactScalarAdmission & ~Copyable>(declaration: OriginalSourceBoundaryDeclaration<Source>,
        left: borrowing OriginalRationalChartReceipt<Source,OriginalBSplineChartSelection,Field>,right: borrowing OriginalRationalChartReceipt<Source,OriginalBSplineChartSelection,Field>,
        scope: borrowing OriginalParameterSelection<Source,Field>,rightFrame: borrowing OriginalParameterFrame<Source,Field>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
}
