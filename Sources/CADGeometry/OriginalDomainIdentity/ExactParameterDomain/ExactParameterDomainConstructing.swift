#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactParameterDomainConstructing: Sendable {
    associatedtype Field: ExactScalarOrdering
    func interval<A: ExactScalarAdmission & ~Copyable>(lower: ExactParameterBound<Field.Value>,
        upper: ExactParameterBound<Field.Value>, includesLower: Bool, includesUpper: Bool,
        using admission: inout A) throws(ExactParameterDomainFailure) -> ExactParameterInterval<Field.Value>
    func empty<A: ExactScalarAdmission & ~Copyable>(using admission: inout A)
        throws(ExactParameterDomainFailure) -> ExactParameterSet<Field>
    func set<A: ExactScalarAdmission & ~Copyable>(intervals: borrowing [ExactParameterInterval<Field.Value>],
        using admission: inout A) throws(ExactParameterDomainFailure) -> ExactParameterSet<Field>
    func union<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactParameterSet<Field>,
        _ rhs: borrowing ExactParameterSet<Field>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> ExactParameterSet<Field>
    func intersection<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactParameterSet<Field>,
        _ rhs: borrowing ExactParameterSet<Field>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> ExactParameterSet<Field>
    func difference<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactParameterSet<Field>,
        _ rhs: borrowing ExactParameterSet<Field>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> ExactParameterSet<Field>
    func product<A: ExactScalarAdmission & ~Copyable>(axes: borrowing [ExactParameterSet<Field>],
        using admission: inout A) throws(ExactParameterDomainFailure) -> ExactParameterProduct<Field>
}
