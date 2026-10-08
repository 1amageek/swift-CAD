#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Parent-owned boundary bindings of the existing common-U ruled construction.
public protocol OriginalRuledSourceReading: Sendable {
    associatedtype First: Sendable
    associatedtype Second: Sendable
    var firstBoundary: OriginalSourceBinding<First> { get }
    var secondBoundary: OriginalSourceBinding<Second> { get }
    var originalLowerU: Double { get }
    var originalUpperU: Double { get }
}
