#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

/// Membership with an explicit ordering field retaining the original axis authority.
public protocol ExactParameterDomainFieldQuerying: ExactParameterDomainQuerying {
    func contains<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Field.Value,
        in selection: borrowing ExactParameterSet<Field>, queryField: Field, using admission: inout A)
        throws(ExactParameterDomainFailure) -> Bool
}
