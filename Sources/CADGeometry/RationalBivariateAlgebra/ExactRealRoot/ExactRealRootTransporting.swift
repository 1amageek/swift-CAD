#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Explicitly transfers a selected original root through a self or ancestor field embedding.
public protocol ExactRealRootTransporting: Sendable {
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
        where Field.Source == Field.Value
    func transport<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<Field>,
        using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRootTransport<Field>
}
