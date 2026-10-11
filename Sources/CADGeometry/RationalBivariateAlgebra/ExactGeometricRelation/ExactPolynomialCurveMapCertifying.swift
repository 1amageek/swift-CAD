#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public protocol ExactPolynomialCurveMapCertifying {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func certify<A: ExactScalarAdmission & ~Copyable>(_ graph: borrowing ExactParametricGraph<Base>,
        using admission: inout A) throws(ExactGeometricRelationFailure) -> ExactPolynomialCurveMapEvidence<Base>
}
