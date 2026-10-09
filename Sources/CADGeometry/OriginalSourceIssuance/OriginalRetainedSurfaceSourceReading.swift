#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original producer owns immutable position laws and their exact authored cells.
/// Every supplied closed cell belongs to the original position domain and its
/// retained denominator is nonzero throughout it. A bounding box or stripped
/// differential field supplies no conformance authority; guarded source domains
/// require their own predicate contract instead of this rectangular cell port.
public protocol OriginalRetainedSurfaceSourceReading:Sendable {
    associatedtype Field:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    var originalField:Field { get }
    var originalPolynomials:ExactPolynomialDomain<Field> { get }
    var originalProofDepth:ExactScalarDepth { get }
    var originalCellCount:Int { get }
    func originalCellLowerBound(at index:Int,axis:Int)->Field.Value
    func originalCellUpperBound(at index:Int,axis:Int)->Field.Value
    func originalCellHomogeneous(at index:Int)->[ExactPolynomial<Field>]
}
