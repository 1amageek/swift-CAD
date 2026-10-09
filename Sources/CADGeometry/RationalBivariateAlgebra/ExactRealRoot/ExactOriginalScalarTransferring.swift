#if ORIGINAL_COORDINATE_ISOLATED_VERIFICATION
import L0
import L2
#elseif L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact compatibility with retained original coordinates, without replaying a relation.
public protocol ExactOriginalScalarTransferring: Sendable {
    func transfer<A: ExactScalarAdmission & ~Copyable>(
        _ values: borrowing [ExactAlgebraicScalar<OriginalExactScalarDomain>],
        into destination: borrowing OriginalExactScalarDomain, using admission: inout A
    ) throws(ExactScalarFailure) -> ExactOriginalScalarTransferReceipt
}
