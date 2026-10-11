#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// An incidence candidate bound to the actual laws, never a certificate of equality.
public struct OriginalRationalSourceBoundaryDeclaration<S: Sendable, L: Sendable, R: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public enum Side: Sendable { case lower, upper }
    public let left: OriginalRationalChartReceipt<S,L,F>
    public let right: OriginalRationalChartReceipt<S,R,F>
    public let leftAxis: Int
    public let rightAxis: Int
    public let leftSide: Side
    public let rightSide: Side
    public init(left: OriginalRationalChartReceipt<S,L,F>, right: OriginalRationalChartReceipt<S,R,F>,
        leftAxis: Int, rightAxis: Int, leftSide: Side, rightSide: Side) {
        self.left = left; self.right = right
        self.leftAxis = leftAxis; self.rightAxis = rightAxis
        self.leftSide = leftSide; self.rightSide = rightSide
    }
}
