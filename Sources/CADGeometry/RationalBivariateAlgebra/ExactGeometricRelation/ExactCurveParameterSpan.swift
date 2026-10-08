#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Maximal connected t projection of one original parameter component.
public struct ExactCurveParameterSpan<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let sourceComponentOrdinal: Int
    public let lower: ExactCurveParameterBoundary<Base>
    public let upper: ExactCurveParameterBoundary<Base>
    public let includesLower: Bool
    public let includesUpper: Bool
    public let firstPrefix: ExactRealCellID<Base>
    public let lastPrefix: ExactRealCellID<Base>
}
