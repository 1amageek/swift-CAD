#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retains the actual child and exact directed authored endpoint coefficients.
public protocol OriginalTraversalSourceReading: Sendable {
    associatedtype Child: Sendable
    associatedtype Coefficient: Sendable
    var originalChild: OriginalSourceBinding<Child> { get }
    var originalStart: Coefficient { get }
    var originalEnd: Coefficient { get }
}
