#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// An authored incidence declaration is a candidate, not a geometric proof.
public struct OriginalSourceBoundaryDeclaration<S: Sendable>: Sendable {
    public enum Side: Sendable { case lower, upper }
    public let left: OriginalSourceChart<S,OriginalBSplineChartSelection>
    public let right: OriginalSourceChart<S,OriginalBSplineChartSelection>
    public let leftAxis: Int
    public let rightAxis: Int
    public let leftSide: Side
    public let rightSide: Side
    public init(left: OriginalSourceChart<S,OriginalBSplineChartSelection>,right: OriginalSourceChart<S,OriginalBSplineChartSelection>,
        leftAxis: Int,rightAxis: Int,leftSide: Side,rightSide: Side) {
        self.left = left; self.right = right; self.leftAxis = leftAxis; self.rightAxis = rightAxis
        self.leftSide = leftSide; self.rightSide = rightSide
    }
}
