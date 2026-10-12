#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// An explicitly selected physical-radian coefficient capability.
public protocol ExactPhysicalAngleCoefficients: ExactScalarArithmetic, ExactScalarOrdering, ExactScalarImporting {
    var originalRadians: Double { get }
    func sine<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) -> Value
    func cosine<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) -> Value
}
