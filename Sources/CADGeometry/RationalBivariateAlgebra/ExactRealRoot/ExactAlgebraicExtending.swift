#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol ExactAlgebraicExtending: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    init<A: ExactScalarAdmission & ~Copyable>(retaining value: borrowing ExactAlgebraicScalar<Base>,
        using admission: inout A) throws(ExactScalarFailure)
    static func base<A: ExactScalarAdmission & ~Copyable>(field: Base, maximumExtensionLevel: Int,
        using admission: inout A) throws(ExactRealRootFailure) -> ExactAlgebraicScalarDomain<Base>
    func adjoin<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<ExactAlgebraicScalarDomain<Base>>,
        using admission: inout A) throws(ExactRealRootFailure) -> ExactAlgebraicExtension<Base>
}
