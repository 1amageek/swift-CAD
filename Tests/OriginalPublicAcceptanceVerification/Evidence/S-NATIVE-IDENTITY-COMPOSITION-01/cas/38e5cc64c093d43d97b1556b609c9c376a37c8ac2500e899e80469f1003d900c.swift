#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalParameterTransporting: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ map: borrowing OriginalParameterTransport<Source,Field>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure)
    func reframed<A: ExactScalarAdmission & ~Copyable>(_ map: borrowing OriginalParameterTransport<Source,Field>,
        to target: borrowing OriginalParameterFrame<Source,Field>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,Field>
    func frame<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>, field: Field,
        support: borrowing [[ExactParameterInterval<Field.Value>]], semantics: [OriginalCoordinateSemantics],
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,Field>
    func periodicLift<A: ExactScalarAdmission & ~Copyable>(from local: borrowing OriginalParameterSelection<Source,Field>,
        to authored: borrowing OriginalParameterFrame<Source,Field>, period: borrowing OriginalSourcePeriodReceipt<Source,Field>,
        cycle: OriginalParameterCycle, limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterPeriodicLift<Source,Field>
    func affine<A: ExactScalarAdmission & ~Copyable>(from local: borrowing OriginalParameterSelection<Source,Field>,
        to authored: borrowing OriginalParameterFrame<Source,Field>, permutation: [Int], gains: [Field.Value], offsets: [Field.Value],
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,Field>
    func forward<A: ExactScalarAdmission & ~Copyable>(_ tuple: borrowing [Field.Value],
        through map: borrowing OriginalParameterTransport<Source,Field>, limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Field.Value]
    func inverse<A: ExactScalarAdmission & ~Copyable>(_ map: borrowing OriginalParameterTransport<Source,Field>,
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,Field>
    func compose<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing OriginalParameterTransport<Source,Field>,
        _ second: borrowing OriginalParameterTransport<Source,Field>, limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,Field>
    func restrict<A: ExactScalarAdmission & ~Copyable>(_ map: borrowing OriginalParameterTransport<Source,Field>,
        to selection: borrowing OriginalParameterSelection<Source,Field>, limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,Field>
}
