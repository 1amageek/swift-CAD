#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// The original affine chart map; coefficients are read in the chosen exact field.
public protocol OriginalParameterImageSourceReading: Sendable {
    associatedtype Child: Sendable
    var originalChild: OriginalSourceBinding<Child> { get }
    var parameterCount: Int { get }
    var hasSpatialAction: Bool { get }
    func childAxis(forOriginalAxis axis: Int) -> Int
    func originalGain<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
        in axis: Int, field: borrowing F, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> F.Value
    func originalOffset<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
        in axis: Int, field: borrowing F, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> F.Value
    func originalSpatialCoefficient<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
        row: Int, column: Int, field: borrowing F, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> F.Value
}
