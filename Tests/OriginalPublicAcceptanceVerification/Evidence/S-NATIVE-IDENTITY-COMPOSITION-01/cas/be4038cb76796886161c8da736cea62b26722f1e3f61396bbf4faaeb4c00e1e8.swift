#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact mathematical pi capability, separate from authored angular labels.
public protocol OriginalPiGenerating: ExactScalarArithmetic, ExactScalarOrdering, ExactScalarImporting {
    func pi<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) -> Value
}
