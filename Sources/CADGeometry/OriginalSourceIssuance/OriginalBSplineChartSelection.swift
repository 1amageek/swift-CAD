#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original native span ordinals; the family issuer validates each selection.
public struct OriginalBSplineChartSelection: Sendable {
    public let spans: [Int]
    public init(spans: [Int]) { self.spans = spans }
}
