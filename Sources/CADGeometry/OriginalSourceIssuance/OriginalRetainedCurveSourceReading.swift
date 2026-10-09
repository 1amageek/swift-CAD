#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// A genuine original producer guarantees each closed cell's position law and
/// nonzero denominator throughout. Descriptors and bounding intervals are not
/// authority; guarded domains use a separate predicate contract.
public protocol OriginalRetainedCurveSourceReading:Sendable {
    associatedtype Field:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    var originalField:Field { get }
    var originalPolynomials:ExactPolynomialDomain<Field> { get }
    var originalProofDepth:ExactScalarDepth { get }
    var originalCellCount:Int { get }
    func originalCellLowerBound(at index:Int)->Field.Value
    func originalCellUpperBound(at index:Int)->Field.Value
    func originalCellHomogeneous(at index:Int)->[ExactPolynomial<Field>]
}
