#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original normalized child bindings and the unchanged minor-arc feasibility policy.
public protocol OriginalRollingBallChildSourceReading: Sendable {
    associatedtype Child: Sendable
    var originalCenter: OriginalSourceBinding<Child> { get }
    var originalFirstContact: OriginalSourceBinding<Child> { get }
    var originalSecondContact: OriginalSourceBinding<Child> { get }
    var originalRadius: Double { get }
    var originalDistanceTolerance: Double { get }
    var originalRadialCrossThreshold: Double { get }
}
