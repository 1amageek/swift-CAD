#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactParameterDomainQuerying: Sendable {
    associatedtype Field: ExactScalarOrdering
    func contains<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Field.Value,
        in selection: borrowing ExactParameterSet<Field>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> Bool
    func setEqual<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactParameterSet<Field>,
        _ rhs: borrowing ExactParameterSet<Field>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> Bool
    func contains<A: ExactScalarAdmission & ~Copyable>(tuple: borrowing [Field.Value],
        in selection: borrowing ExactParameterProduct<Field>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> Bool
}
