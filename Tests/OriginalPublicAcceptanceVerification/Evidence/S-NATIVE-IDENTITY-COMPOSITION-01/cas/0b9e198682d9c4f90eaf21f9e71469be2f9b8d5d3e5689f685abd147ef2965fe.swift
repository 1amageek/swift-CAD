#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol ExactRealRootQuerying: Sendable {
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func separate<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactRealRoot<Field>,
        _ rhs: borrowing ExactRealRoot<Field>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSeparation<Field>
    func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactRealRoot<Field>,
        _ rhs: borrowing ExactRealRoot<Field>, using admission: inout A) throws(ExactRealRootFailure) -> ExactOrder
    func refine<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<Field>,
        maximumWidth: Field.Value, using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRoot<Field>
    func refine<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<Field>,
        toExactValue: Field.Value, using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRoot<Field>
    func refine<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<Field>,
        usingDefiningDivisor divisor: borrowing ExactRealRootSource<Field>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRoot<Field>
    func refine<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<Field>,
        usingVanishingLaw law: borrowing ExactRealRootSource<Field>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRoot<Field>
    func sign<A: ExactScalarAdmission & ~Copyable>(of polynomial: borrowing ExactRealRootSource<Field>,
        at root: borrowing ExactRealRoot<Field>, using admission: inout A) throws(ExactRealRootFailure) -> ExactSign
    func signs<A: ExactScalarAdmission & ~Copyable>(of polynomials: [ExactRealRootSource<Field>],
        at root: borrowing ExactRealRoot<Field>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSigns<Field>

}
