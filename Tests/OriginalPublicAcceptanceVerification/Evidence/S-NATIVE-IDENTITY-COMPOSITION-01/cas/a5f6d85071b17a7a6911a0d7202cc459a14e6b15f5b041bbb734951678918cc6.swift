#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// A finite closed chart of an otherwise unbounded original line.
public struct OriginalLinearChartSelection: Sendable {
    public let lower: Double
    public let upper: Double
    public init(lower: Double, upper: Double) { self.lower = lower; self.upper = upper }
}
